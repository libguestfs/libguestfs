# libguestfs Perl bindings -*- perl -*-
# Copyright (C) 2009 Red Hat Inc.
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
use Test::More tests => 11;

use Sys::Guestfs;

my $h = Sys::Guestfs->new ();
ok ($h);
open FILE, ">test.img";
truncate FILE, 500*1024*1024;
close FILE;
ok (1);

$h->add_drive ("test.img");
ok (1);

$h->launch ();
ok (1);

$h->pvcreate ("/dev/sda");
ok (1);
$h->vgcreate ("VG", ["/dev/sda"]);
ok (1);
$h->lvcreate ("LV1", "VG", 200);
ok (1);
$h->lvcreate ("LV2", "VG", 200);
ok (1);

my @lvs = $h->lvs ();
if (@lvs != 2 || $lvs[0] ne "/dev/VG/LV1" || $lvs[1] ne "/dev/VG/LV2") {
    die "h->lvs() returned incorrect result"
}
ok (1);

$h->sync ();
ok (1);

undef $h;
ok (1);

unlink ("test.img");
