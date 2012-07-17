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
use Test::More tests => 7;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
ok ($g);

$g->set_verbose (1);
ok ($g->get_verbose () == 1, "verbose not true");
$g->set_verbose (0);
ok ($g->get_verbose () == 0, "verbose not false");
$g->set_autosync (1);
ok ($g->get_autosync () == 1, "autosync not true");
$g->set_autosync (0);
ok ($g->get_autosync () == 0, "autosync not false");

# This probably doesn't work at the moment because
# the binding for set_path does not ensure the string
# remains around for the lifetime of the handle.
#$g->set_path (".");
#ok ($g->get_path () eq ".", "path not dot");
#$g->set_path (undef);
#ok ($g->get_path () ne "", "path is empty");

$g->add_drive ("/dev/null");
ok (1, "add drive");
$g->add_cdrom ("/dev/zero");
ok (1, "add cdrom");
