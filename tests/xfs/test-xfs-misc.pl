#!/usr/bin/env perl
# libguestfs
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

# Miscellaneous xfs features.

use strict;
use warnings;

use Sys::Guestfs;

exit 77 if $ENV{SKIP_TEST_XFS_MISC_PL};

my $g = Sys::Guestfs->new ();

$g->add_drive_scratch (1024*1024*1024);
$g->launch ();

# If xfs is not available, bail.
unless ($g->feature_available (["xfs"])) {
    warn "$0: skipping test because xfs is not available\n";
    exit 77;
}

$g->part_disk ("/dev/sda", "mbr");

$g->mkfs ("xfs", "/dev/sda1");

# Setting label.
$g->set_label ("/dev/sda1", "newlabel");
my $label = $g->vfs_label ("/dev/sda1");
die "unexpected label: expecting 'newlabel' but got '$label'"
    unless $label eq "newlabel";

# Setting UUID.
my $newuuid = "01234567-0123-0123-0123-0123456789ab";
$g->set_uuid ("/dev/sda1", $newuuid);
my $uuid = $g->vfs_uuid ("/dev/sda1");
die "unexpected UUID: expecting '$newuuid' but got '$uuid'"
    unless $uuid eq $newuuid;

$g->shutdown ();
$g->close ();
