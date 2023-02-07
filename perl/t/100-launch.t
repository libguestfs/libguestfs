# libguestfs Perl bindings -*- perl -*-
# Copyright (C) 2009-2023 Red Hat Inc.
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
use Test::More tests => 25;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
ok ($g);
$g->add_drive_scratch (500*1024*1024);
ok (1);

$g->launch ();
ok (1);

$g->pvcreate ("/dev/sda");
ok (1);
$g->vgcreate ("VG", ["/dev/sda"]);
ok (1);
$g->lvcreate ("LV1", "VG", 200);
ok (1);
$g->lvcreate ("LV2", "VG", 200);
ok (1);

my @lvs = $g->lvs ();
if (@lvs != 2 || $lvs[0] ne "/dev/VG/LV1" || $lvs[1] ne "/dev/VG/LV2") {
    die "g->lvs() returned incorrect result"
}
ok (1);

$g->mkfs ("ext2", "/dev/VG/LV1");
ok (1);
$g->mount ("/dev/VG/LV1", "/");
ok (1);
$g->mkdir ("/p");
ok (1);
$g->touch ("/q");
ok (1);

my @dirs = $g->readdir ("/");
@dirs = sort { $a->{name} cmp $b->{name} } @dirs;
ok (@dirs == 5);
ok ($dirs[0]{name} eq ".");
ok ($dirs[0]{ftyp} eq "d");
ok ($dirs[1]{name} eq "..");
ok ($dirs[1]{ftyp} eq "d");
ok ($dirs[2]{name} eq "lost+found");
ok ($dirs[2]{ftyp} eq "d");
ok ($dirs[3]{name} eq "p");
ok ($dirs[3]{ftyp} eq "d");
ok ($dirs[4]{name} eq "q");
ok ($dirs[4]{ftyp} eq "r");

$g->shutdown ();
ok (1);

undef $g;
ok (1)
