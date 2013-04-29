# libguestfs Perl bindings -*- perl -*-
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
use Test::More tests => 6;

use Sys::Guestfs;

my $g1 = Sys::Guestfs->new ();
ok ($g1);
my $g2 = Sys::Guestfs->new ();
ok ($g2);
my $g3 = Sys::Guestfs->new ();
ok ($g3);

$g1->set_path ("1");
$g2->set_path ("2");
$g3->set_path ("3");

ok ($g1->get_path () eq "1");
ok ($g2->get_path () eq "2");
ok ($g3->get_path () eq "3");
