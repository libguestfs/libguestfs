#!/usr/bin/perl
# libguestfs
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

# Test btrfs subvolume list and btrfs subvolume default-id.

use strict;
use warnings;

use Sys::Guestfs;
use Sys::Guestfs::Lib qw(feature_available);

my $testimg = "test1.img";

unlink $testimg;
open FILE, ">$testimg" or die "$testimg: $!";
truncate FILE, 1024*1024*1024 or die "$testimg: truncate: $!";
close FILE or die "$testimg: $!";

my $g = Sys::Guestfs->new ();

$g->add_drive_opts ($testimg, format => "raw");
$g->launch ();

# If btrfs is not available, bail.
unless (feature_available ($g, "btrfs")) {
    warn "$0: skipping test because btrfs is not available\n";
    exit 77;
}

$g->part_disk ("/dev/sda", "mbr");

$g->mkfs_btrfs (["/dev/sda1"]);
$g->mount ("/dev/sda1", "/");

$g->btrfs_subvolume_create ("/test1");
$g->mkdir ("/test1/foo");
$g->btrfs_subvolume_create ("/test2");

my @vols = $g->btrfs_subvolume_list ("/");

# Check the subvolume list, and extract the subvolume ID of path 'test1',
# and the top level ID (which should be the same for both subvolumes).
die ("expected 2 subvolumes, but got ", 0+@vols, " instead") unless @vols == 2;

my %ids;
my $top_level_id;
foreach (@vols) {
    my $path = $_->{btrfssubvolume_path};
    my $id = $_->{btrfssubvolume_id};
    my $top = $_->{btrfssubvolume_top_level_id};

    if (!defined $top_level_id) {
        $top_level_id = $top;
    } elsif ($top_level_id != $top) {
        die "top_level_id fields are not all the same";
    }

    $ids{$path} = $id;
}

die "no subvolume path 'test1' found" unless exists $ids{test1};

my $test1_id = $ids{test1};

$g->btrfs_subvolume_set_default ($test1_id, "/");
$g->umount ("/");
$g->mount ("/dev/sda1", "/");
# This was originally /test1/foo, but now that we changed the
# default ID to 'test1', /test1 is mounted as /, so:
$g->mkdir ("/foo/bar");

$g->btrfs_subvolume_set_default ($top_level_id, "/");
$g->umount ("/");
$g->mount ("/dev/sda1", "/");
# Now we're back to the original default volume, so this should work:
$g->mkdir ("/test1/foo/bar/baz");

$g->shutdown ();
$g->close ();

unlink $testimg or die "$testimg: unlink: $!";
