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

use strict;
use warnings;
use Test::More tests => 4;

use Sys::Guestfs;

my $h = Sys::Guestfs->new ();
ok ($h);

$h->add_drive_opts ("/dev/null");
ok (1);

$h->add_drive_opts ("/dev/null", readonly => 1);
ok (1);

$h->add_drive_opts ("/dev/null", format => "raw", readonly => 0);
ok (1);
