#!/usr/bin/env perl
# libguestfs
# Copyright (C) 2016 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;

use POSIX qw(uname);

my $script = $ENV{script};

unless (exists $ENV{SLOW} && $ENV{SLOW} eq "1") {
    print STDERR "$script: use 'make check-slow' to run this test\n";
    exit 77
}

# This test requires the perl 'Expect' module.  If it doesn't
# exist, skip the test.
eval "use Expect";

unless (exists $INC{"Expect.pm"}) {
    print STDERR "$script: test skipped because there is no perl Expect module\n";
    exit 77
}

die "$script: guestname parameter not set, don't run this test directly"
    unless @ARGV == 1;
my $guestname = $ARGV[0];

my $disk = "password-$guestname.img";
eval { unlink $disk };

my $logfile = "password-$guestname.log";
eval { unlink $logfile };

# If the guest doesn't exist in virt-builder, skip.  This is because
# we test some RHEL guests which most users won't have access to.
if (system ("virt-builder -l $guestname >/dev/null 2>&1") != 0) {
    print STDERR "$script: test skipped because \"$guestname\" not known to virt-builder.\n";
    exit 77
}

# We can only run this test on x86_64.
my ($sysname, $nodename, $release, $version, $machine) = uname ();
if ($machine ne "x86_64") {
    print STDERR "$script: test skipped because !x86_64\n";
    exit 77
}

# Check qemu is installed.
my $qemu = "qemu-system-x86_64";
if (system ("$qemu -help >/dev/null 2>&1") != 0) {
    print STDERR "$script: test skipped because $qemu not found.\n";
    exit 77
}

# Some guests need special virt-builder parameters.
# See virt-builder --notes $guestname and builder/test-console.sh
my @extra = ();
if ($guestname eq "debian-7") {
    push @extra, "--edit",
        '/etc/inittab: s,^#([1-9].*respawn.*/sbin/getty.*),$1,';
}
elsif ($guestname eq "debian-8" || $guestname eq "ubuntu-16.04") {
    # These commands are required to fix the serial console.
    # See https://askubuntu.com/questions/763908/ubuntu-16-04-has-no-vmware-console-access-once-booted-on-vmware-vsphere-5-5-clus/764476#764476
    push @extra, "--edit",
        '/etc/default/grub: s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"/';
    push @extra, "--run-command", "update-grub";
}

# Set a random root password under our control.
# http://www.perlmonks.org/?node_id=233023
my @chars = ("a".."z", "0".."9");
my $password = "";
$password .= $chars[rand @chars] for 1..8;

# Build the guest.
system ("virt-builder", $guestname, "--quiet",
        "-o", $disk,
        "--root-password", "password:$password",
        @extra) == 0
    or die "$script: virt-builder failed, see previous errors";

# Run qemu and make sure we get to the login prompt.
my $exp = Expect->spawn ($qemu,
                         "-nodefconfig", "-display", "none",
                         "-machine", "accel=kvm:tcg",
                         "-m", "1024", "-boot", "c",
                         "-drive", "file=$disk,format=raw,if=ide",
                         "-serial", "stdio")
    or die "$script: Expect could not spawn $qemu: $!\n";

$exp->log_file ($logfile);

my $timeout = 5 * 60;
my $r;
$r = $exp->expect ($timeout, 'login:');
unless (defined $r) {
    die "$script: guest did not print the 'login:' prompt within\n$timeout seconds, or exited before getting to the prompt.\n";
}

# Try to log in.
$exp->send ("root\n");
$r = $exp->expect ($timeout, 'assword:');
unless (defined $r) {
    die "$script: guest did not print the password prompt within\n$timeout seconds, or exited before getting to the prompt.\n";
}
$exp->send ("$password\n");

# Send a simple command; try to find some expected output.
$exp->send ("ls -1 /\n");

$timeout = 60;
$r = $exp->expect ($timeout, 'home');

unless (defined $r) {
    die "$script: guest did not respond to a simple 'ls' command, the login probably failed\n";
}

$exp->hard_close ();

# Successful exit, so remove disk image and log file.
unlink $disk;
unlink $logfile;

exit 0
