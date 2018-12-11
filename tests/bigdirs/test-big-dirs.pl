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

# Test long directories and protocol limits.

use strict;
use warnings;

use Sys::Guestfs;

unless ($ENV{SLOW}) {
    print "$0: use 'make check-slow' to run this test\n";
    exit 77;
}

if ($ENV{SKIP_TEST_BIG_DIRS_PL}) {
    print "$0: test skipped because SKIP_TEST_BIG_DIRS_PL is set\n";
    exit 77;
}

my $g = Sys::Guestfs->new ();

# Create a 2 GB test file.  Don't worry, it's sparse.

my $nr_files = 1000000;
my $image_size = 2*1024*1024*1024;

$g->add_drive_scratch ($image_size);

$g->launch ();

$g->part_disk ("/dev/sda", "mbr");
$g->mkfs ("ext4", "/dev/sda1");
$g->mke2fs ("/dev/sda1", fstype => "ext4", bytesperinode => 2048);
$g->mount ("/dev/sda1", "/");

my %df = $g->statvfs ("/");
die "$0: internal error: not enough inodes on filesystem"
    unless $df{favail} > $nr_files;

# Create a very large directory.  The aim is that the number of files
# * length of each filename should be longer than a protocol message
# (currently 4 MB).
$g->mkdir ("/dir");
$g->fill_dir ("/dir", $nr_files);

# Listing the directory should be OK.
my @filenames = $g->ls ("/dir");

# Check the names (they should be sorted).
die "incorrect number of filenames returned by \$g->ls"
    unless @filenames == $nr_files;
for (my $i = 0; $i < $nr_files; ++$i) {
    if ($filenames[$i] ne sprintf ("%08d", $i)) {
        die "unexpected filename at index $i: $filenames[$i]";
    }
}

# Check that lstatlist, lxattrlist and readlinklist return the
# expected number of entries.
my @a;

@a = $g->lstatlist ("/dir", \@filenames);
die unless @a == $nr_files;
@a = $g->lxattrlist ("/dir", \@filenames);
die unless @a == $nr_files;
@a = $g->readlinklist ("/dir", \@filenames);
die unless @a == $nr_files;

$g->shutdown ();
$g->close ();
