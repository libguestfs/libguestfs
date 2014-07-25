#!/usr/bin/perl
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

# Test hot-adding and -removing disks.

use strict;
use warnings;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();

exit 77 if $ENV{SKIP_TEST_HOT_REMOVE_PL};

# Skip the test if the default backend isn't libvirt, since only
# the libvirt backend supports hotplugging.
my $backend = $g->get_backend ();
unless ($backend eq "libvirt" || $backend =~ /^libvirt:/) {
    print "$0: test skipped because backend ($backend) is not libvirt\n";
    exit 77
}

# Create some temporary disks.
$g->disk_create ("test-hot-remove-1.img", "raw", 512 * 1024 * 1024);
$g->disk_create ("test-hot-remove-2.img", "raw", 512 * 1024 * 1024);
$g->disk_create ("test-hot-remove-3.img", "qcow2", 1024 * 1024 * 1024,
                 preallocation => "metadata");

# Hot-add them.  Labels are required.
$g->add_drive ("test-hot-remove-1.img", label => "a"); # autodetect format
$g->add_drive ("test-hot-remove-2.img", label => "b", format => "raw", readonly => 1);
$g->add_drive ("test-hot-remove-3.img", label => "c", format => "qcow2");

# Remove them (before launch).
$g->remove_drive ("a");
$g->remove_drive ("b");
$g->remove_drive ("c");

$g->launch ();

# There should be no drives yet.
my @devices = $g->list_devices ();
die unless 0 == @devices;

# Add them again (after launch).
$g->add_drive ("test-hot-remove-1.img", label => "a"); # autodetect format
$g->add_drive ("test-hot-remove-2.img", label => "b", format => "raw", readonly => 1);
$g->add_drive ("test-hot-remove-3.img", label => "c", format => "qcow2");

# Check we can use the disks immediately.
$g->part_disk ("/dev/disk/guestfs/a", "mbr");
$g->mkfs ("ext2", "/dev/disk/guestfs/c");
$g->mkfs ("ext2", "/dev/disk/guestfs/a1");

# Remove them (hotplug this time).
$g->remove_drive ("a");
$g->remove_drive ("b");
$g->remove_drive ("c");

# There should be no drives remaining.
@devices = $g->list_devices ();
die unless 0 == @devices;

$g->shutdown ();
$g->close ();

unlink "test-hot-remove-1.img";
unlink "test-hot-remove-2.img";
unlink "test-hot-remove-3.img";

exit 0
