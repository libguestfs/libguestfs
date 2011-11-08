# libguestfs Perl bindings -*- perl -*-
# Copyright (C) 2010 Red Hat Inc.
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

# Test implicit vs explicit closes of the handle (RHBZ#602592).

use strict;
use warnings;
use Test::More tests => 10;

use Sys::Guestfs;

my $g;

$g = Sys::Guestfs->new ();
ok($g);
$g->close ();                   # explicit close
ok($g);
undef $g;                       # implicit close - should be no error/warning
ok(1);

# Expect an error if we call a method on a closed handle.
$g = Sys::Guestfs->new ();
ok($g);
$g->close ();
ok($g);
eval { $g->set_memsize (512); };
ok($g);
ok($@ && $@ =~ /closed handle/);
undef $g;
ok(1);

# Try calling a method without a blessed reference.  This should
# give a different error.
eval { Sys::Guestfs::set_memsize (undef, 512); };
ok ($@ && $@ =~ /not.*blessed/);
eval { Sys::Guestfs::set_memsize (42, 512); };
ok ($@ && $@ =~ /not.*blessed/);
