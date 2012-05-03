#!/usr/bin/perl -w
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=701814

use strict;

use Sys::Guestfs;
use Sys::Guestfs::Lib qw(open_guest);

$ENV{FAKE_LIBVIRT_XML} = "rhbz701814-faked.xml";
my $abs_srcdir = $ENV{abs_srcdir};

my $g = open_guest (["winxppro"],
                    address => "test://$abs_srcdir/rhbz701814-node.xml");
