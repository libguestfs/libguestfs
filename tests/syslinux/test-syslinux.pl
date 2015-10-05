#!/usr/bin/env perl
# Copyright (C) 2013 Red Hat Inc.
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

# This ambitious script creates a complete, bootable guest.

use strict;
use warnings;

use Sys::Guestfs;

exit 77 if $ENV{SKIP_TEST_SYSLINUX_PL};

my $bootloader = $ENV{BOOTLOADER} || "syslinux";

my $disk = "$bootloader-guest.img";

# Find prerequisites.
my $mbr;
my @mbr_paths = (
  "/usr/share/syslinux/mbr.bin",
  "/usr/lib/syslinux/mbr.bin",
  "/usr/lib/syslinux/mbr/mbr.bin",
  "/usr/lib/syslinux/bios/mbr.bin",
  "/usr/lib/SYSLINUX/mbr.bin"
);
foreach my $m (@mbr_paths) {
  if (-f $m) {
    $mbr = $m;
    last;
  }
}
unless (defined $mbr) {
    print "$0: mbr.bin (from SYSLINUX) not found, skipping test\n";
    exit 77;
}
print "mbr: $mbr\n";

my $mbr_data;
{
    local $/ = undef;
    open MBR, "$mbr" or die "$mbr: $!";
    $mbr_data = <MBR>;
}
die "invalid mbr.bin" unless length ($mbr_data) == 440;

my $kernel = `ls -1rv /boot/vmlinuz* | head -1`;
chomp $kernel;
unless ($kernel) {
    print "$0: kernel could not be found, skipping test\n";
    exit 77;
}
print "kernel: $kernel\n";

my $g = Sys::Guestfs->new ();

# Create the disk.
$g->disk_create ($disk, "raw", 100*1024*1024);

$g->add_drive ($disk, format => "raw");
$g->launch ();

unless ($g->feature_available ([$bootloader])) {
    print "$0: skipping test because '$bootloader' feature is not available\n";
    exit 77
}

# Format the disk.
$g->part_disk ("/dev/sda", "mbr");

if ($bootloader eq "syslinux") {
    $g->mkfs ("msdos", "/dev/sda1");
} else {
    $g->mkfs ("ext3", "/dev/sda1");
}
$g->mount ("/dev/sda1", "/");

# Install the kernel.
$g->upload ($kernel, "/vmlinuz");

# Install the SYSLINUX configuration file.
$g->write ("/syslinux.cfg", <<_END);
DEFAULT linux
LABEL linux
  SAY Booting the kernel from /vmlinuz
  KERNEL vmlinuz
  APPEND ro root=/dev/sda1
_END

$g->umount_all ();

# Install the bootloader.
$g->pwrite_device ("/dev/sda", $mbr_data, 0);
if ($bootloader eq "syslinux") {
    $g->syslinux ("/dev/sda1");
} else {
    $g->mount ("/dev/sda1", "/");
    $g->extlinux ("/");
    $g->umount ("/");
}
$g->part_set_bootable ("/dev/sda", 1, 1);

# Finish off.
$g->shutdown ();
