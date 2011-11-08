# libguestfs Perl bindings -*- perl -*-
# Copyright (C) 2011 Red Hat Inc.
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

# Test $g->last_errno (RHBZ#672491).

use strict;
use warnings;
use Test::More tests => 15;

use Errno;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
ok ($g);

open FILE, ">test.img";
truncate FILE, 500*1024*1024;
close FILE;
ok (1);

$g->add_drive_opts ("test.img", format => "raw");
ok (1);

$g->launch ();
ok (1);

$g->part_disk ("/dev/sda", "mbr");
ok (1);
$g->mkfs ("ext2", "/dev/sda1");
ok (1);

$g->mount_options ("", "/dev/sda1", "/");
ok (1);

# Directory doesn't exist, so this mkdir should succeed.
$g->mkdir ("/foo");
ok (1);

# Directory exists, we should be able to recover gracefully.
eval {
    $g->mkdir ("/foo");
};
ok ($@);
my $err = $g->last_errno ();
ok ($err > 0);
ok ($err == Errno::EEXIST());

# Can't create subdirectories with missing parents; this should
# be a different errno.
eval {
    $g->mkdir ("/bar/baz");
};
ok ($@);
$err = $g->last_errno ();
ok ($err > 0);
ok ($err != Errno::EEXIST());

undef $g;
ok (1);

unlink ("test.img");
