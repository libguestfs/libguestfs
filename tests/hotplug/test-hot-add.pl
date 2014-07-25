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

# Test hot-adding disks.

use strict;
use warnings;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();

exit 77 if $ENV{SKIP_TEST_HOT_ADD_PL};

# Skip the test if the default backend isn't libvirt, since only
# the libvirt backend supports hotplugging.
my $backend = $g->get_backend ();
unless ($backend eq "libvirt" || $backend =~ /^libvirt:/) {
    print "$0: test skipped because backend ($backend) is not libvirt\n";
    exit 77
}

# We don't need to add disks before launch.
$g->launch ();

# Create some temporary disks.
$g->disk_create ("test-hot-add-1.img", "raw", 512 * 1024 * 1024);
$g->disk_create ("test-hot-add-2.img", "raw", 512 * 1024 * 1024);
$g->disk_create ("test-hot-add-3.img", "qcow2", 1024 * 1024 * 1024,
                 preallocation => "metadata");

# Hot-add them.  Labels are required.
$g->add_drive ("test-hot-add-1.img", label => "a"); # autodetect format
$g->add_drive ("test-hot-add-2.img", label => "b", format => "raw", readonly => 1);
$g->add_drive ("test-hot-add-3.img", label => "c", format => "qcow2");

# Check we can use the disks immediately.
$g->part_disk ("/dev/disk/guestfs/a", "mbr");
$g->mkfs ("ext2", "/dev/disk/guestfs/c");
$g->mkfs ("ext2", "/dev/disk/guestfs/a1");

$g->shutdown ();
$g->close ();

unlink "test-hot-add-1.img";
unlink "test-hot-add-2.img";
unlink "test-hot-add-3.img";

exit 0
