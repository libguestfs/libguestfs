#!/usr/bin/env perl
# Copyright (C) 2012 Red Hat Inc.
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

use File::Temp qw/tempdir/;

use Sys::Guestfs;

# These are two SELinux labels that we assume everyone is allowed to
# set under any policy.
my $label1 = "unconfined_u:object_r:user_tmp_t:s0";
my $label2 = "unconfined_u:object_r:user_home_t:s0";

my $prog = $0;
$prog =~ s{.*/}{};

my $srcdir = $ENV{srcdir};
die "\$srcdir is not defined" unless $srcdir;

my $errors = 0;

if (@ARGV == 3 && $ARGV[0] eq "--test") {
    run_fuse_tests ($ARGV[1], $ARGV[2]);
}

if (@ARGV != 2) {
    print STDERR "$0: incorrect number of parameters for test\n";
    exit 1
}

my $test_type = $ARGV[0];
die unless $test_type eq "xattrs" || $test_type eq "selinux";
my $test_via = $ARGV[1];
die unless $test_via eq "direct" || $test_via eq "fuse";

my $env_name = "SKIP_TEST_SELINUX_" . uc ($test_type) . "_" . uc ($test_via);
if ($ENV{$env_name}) {
    print "$prog $test_type $test_via: test skipped because $env_name is set.\n";
    exit 77
}

# SELinux labelling won't work (and can be skipped) if SELinux isn't
# installed or isn't enabled on the host.
if ($test_type eq "selinux") {
    $_ = qx{getenforce 2>&1 ||:};
    chomp;
    if ($_ ne "Enforcing" && $_ ne "Permissive") {
        print "$prog $test_type $test_via: test skipped because SELinux is not enabled.\n";
        exit 77
    }
}

# Skip FUSE test if the kernel module is not available.
if ($test_via eq "fuse") {
    unless (-w "/dev/fuse") {
        print "$prog $test_type $test_via: test skipped because there is no /dev/fuse.\n";
        exit 77
    }
}

# For FUSE xattr test, setfattr program is required.
if ($test_type eq "xattrs" && $test_via eq "fuse") {
    if (system ("setfattr --help >/dev/null 2>&1") != 0) {
        print "$prog $test_type $test_via: test skipped because 'setfattr' is not installed.\n";
        exit 77
    }
}

# For SELinux on FUSE test, chcon program is required.
if ($test_type eq "selinux" && $test_via eq "fuse") {
    if (system ("chcon --help >/dev/null 2>&1") != 0) {
        print "$prog $test_type $test_via: test skipped because 'chcon' is not installed.\n";
        exit 77
    }
}

# SELinux on FUSE test won't work until SELinux (or FUSE) is fixed.
# See:
# https://bugzilla.redhat.com/show_bug.cgi?id=811217
# https://bugzilla.redhat.com/show_bug.cgi?id=812798#c42
if ($test_type eq "selinux" && $test_via eq "fuse") {
    print "$prog $test_type $test_via: test skipped because SELinux and FUSE\n";
    print "don't work well together:\n";
    print "https://bugzilla.redhat.com/show_bug.cgi?id=811217\n";
    print "https://bugzilla.redhat.com/show_bug.cgi?id=812798#c42\n";
    exit 77;
}

# Create a filesystem that could support xattrs and SELinux labels.
my $g = Sys::Guestfs->new ();

$g->add_drive_scratch (256*1024*1024);
$g->launch ();

unless ($g->feature_available (["linuxxattrs"])) {
    print "$prog $test_type $test_via: test skipped because 'linuxxattrs' feature not available.\n";
    $g->close ();
    exit 77
}

$g->part_disk ("/dev/sda", "mbr");
$g->mkfs ("ext4", "/dev/sda1");

$g->mount_options ("user_xattr", "/dev/sda1", "/");

# Run the test.
if ($test_via eq "direct") {
    if ($test_type eq "xattrs") {
        xattrs_direct ();
    } elsif ($test_type eq "selinux") {
        selinux_direct ();
    } else {
        die "unknown test type: $test_type";
    }
} else {
    # Make a local mountpoint and mount it.
    my $mpdir = tempdir (CLEANUP => 1);
    $g->mount_local ($mpdir);

    # Run the test in another process.
    my $pid = fork ();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        exec ("$srcdir/run-test.pl", "--test", $mpdir, $test_type);
        die "run-test.pl: exec failed: $!\n";
    }

    $g->mount_local_run ();

    waitpid ($pid, 0);
    $errors++ if $?;
}

# Finish up.
$g->shutdown ();
$g->close ();

exit ($errors == 0 ? 0 : 1);

# Run the FUSE tests in a subprocess.
sub run_fuse_tests
{
    my $mpdir = shift;
    my $test_type = shift; # "xattrs" or "selinux"

    if ($test_type eq "xattrs") {
        xattrs_fuse ($mpdir);
    } elsif ($test_type eq "selinux") {
        selinux_fuse ($mpdir);
    } else {
        die "unknown test type: $test_type";
    }

    # Unmount the test directory.
    if (system ("../../fuse/guestunmount", $mpdir) != 0) {
        die "failed to unmount FUSE directory\n";
    }

    exit ($errors == 0 ? 0 : 1);
}

# Test extended attributes, using the libguestfs API directly.
sub xattrs_direct
{
    $g->touch ("/test");
    $g->setxattr ("user.test", "test content", 12, "/test");
    my $attrval = $g->getxattr ("/test", "user.test");
    if ($attrval ne "test content") {
        print STDERR "$prog: failed to set or get xattr using API.\n";
        $errors++;
    }
    my @xattrs = $g->getxattrs ("/test");
    my $found = 0;
    foreach (@xattrs) {
        if ($_->{attrname} eq "user.test" && $_->{attrval} eq "test content") {
            $found++;
        }
    }
    if ($found != 1) {
        print STDERR "$prog: user.test xattr not returned by getxattrs.\n";
        $errors++;
    }
    $g->removexattr ("user.test", "/test");
    @xattrs = $g->getxattrs ("/test");
    $found = 0;
    foreach (@xattrs) {
        if ($_->{attrname} eq "user.test") {
            $found++;
        }
    }
    if ($found != 0) {
        print STDERR "$prog: user.test xattr not removed by removexattr.\n";
        $errors++;
    }
}

# Test extended attributes, over FUSE.
sub xattrs_fuse
{
    my $mpdir = shift;

    open FILE, "> $mpdir/test" or die "$mpdir/test: $!";
    print FILE "test\n";
    close FILE;

    system ("setfattr", "-n", "user.test", "-v", "test content", "$mpdir/test")
        == 0 or die "setfattr: $!";
    my @xattrs = qx{ getfattr -m '.*' -d $mpdir/test };
    my $found = 0;
    foreach (@xattrs) {
        if (m/^user.test="test content"$/) {
            $found++;
        }
    }
    if ($found != 1) {
        print STDERR "$prog: user.test xattr not returned by getfattr.\n";
        $errors++;
    }

    system ("setfattr", "-x", "user.test", "$mpdir/test")
        == 0 or die "setfattr: $!";
    @xattrs = qx{ getfattr -m '.*' -d $mpdir/test };
    $found = 0;
    foreach (@xattrs) {
        if (m/^user.test=$/) {
            $found++;
        }
    }
    if ($found != 0) {
        print STDERR "$prog: user.test xattr not removed by setfattr -x.\n";
        $errors++;
    }
}

# Test SELinux labels, using the libguestfs API directly.
sub selinux_direct
{
    $g->touch ("/test");

    $g->setxattr ("security.selinux", $label1, length $label1, "/test");
    my $attrval = $g->getxattr ("/test", "security.selinux");
    if ($attrval ne $label1) {
        print STDERR "$prog: failed to set or get selinux label '$label1' using API.\n";
        $errors++;
    }

    $g->setxattr ("security.selinux", $label2, length $label2, "/test");
    $attrval = $g->getxattr ("/test", "security.selinux");
    if ($attrval ne $label2) {
        print STDERR "$prog: failed to set or get selinux label '$label2' using API.\n";
        $errors++;
    }

    my @xattrs = $g->getxattrs ("/test");
    my $found = 0;
    foreach (@xattrs) {
        if ($_->{attrname} eq "security.selinux" && $_->{attrval} eq $label2) {
            $found++;
        }
    }
    if ($found != 1) {
        print STDERR "$prog: security.selinux xattr not returned by getxattrs.\n";
        $errors++;
    }
    $g->removexattr ("security.selinux", "/test");
    @xattrs = $g->getxattrs ("/test");
    $found = 0;
    foreach (@xattrs) {
        if ($_->{attrname} eq "security.selinux") {
            $found++;
        }
    }
    if ($found != 0) {
        print STDERR "$prog: security.selinux xattr not removed by removexattr.\n";
        $errors++;
    }
}

# Test SELinux labels, over FUSE.
sub selinux_fuse
{
    my $mpdir = shift;

    open FILE, "> $mpdir/test" or die "$mpdir/test: $!";
    print FILE "test\n";
    close FILE;

    system ("chcon", $label1, "$mpdir/test") == 0 or die "chcon: $!";
    $_ = qx{ ls -Z $mpdir/test | awk '{print $4}' };
    chomp;
    if ($_ ne $label1) {
        print STDERR "$prog: failed to set of get selinux label '$label1' using FUSE.\n";
        $errors++;
    }

    system ("chcon", $label2, "$mpdir/test") == 0 or die "chcon: $!";
    $_ = qx{ ls -Z $mpdir/test | awk '{print $4}' };
    chomp;
    if ($_ ne $label2) {
        print STDERR "$prog: failed to set of get selinux label '$label2' using FUSE.\n";
        $errors++;
    }
}
