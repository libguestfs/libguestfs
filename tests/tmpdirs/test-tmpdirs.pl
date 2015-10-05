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

# Test logic for setting location of tmpdir and cachedir.

use strict;
use warnings;

use Sys::Guestfs;
use File::Temp qw(tempdir);

# Remove any environment variables that may have been set by the
# user or the ./run script which could affect this test.
delete $ENV{LIBGUESTFS_TMPDIR};
delete $ENV{LIBGUESTFS_CACHEDIR};
delete $ENV{TMPDIR};

my $g;

# Defaults with no environment variables set.
$g = Sys::Guestfs->new ();
die unless $g->get_tmpdir () eq "/tmp";
die unless $g->get_cachedir () eq "/var/tmp";

# Create some test directories.
my $a = tempdir (CLEANUP => 1);
my $b = tempdir (CLEANUP => 1);
my $c = tempdir (CLEANUP => 1);

# Setting environment variables.
$ENV{LIBGUESTFS_TMPDIR} = $a;
$ENV{LIBGUESTFS_CACHEDIR} = $b;
$ENV{TMPDIR} = $c;

$g = Sys::Guestfs->new ();
die unless $g->get_tmpdir () eq $a;
die unless $g->get_cachedir () eq $b;

# Creating a handle which isn't affected by environment variables.
$g = Sys::Guestfs->new (environment => 0);
die unless $g->get_tmpdir () eq "/tmp";
die unless $g->get_cachedir () eq "/var/tmp";

# Uses TMPDIR if the others are not set.
delete $ENV{LIBGUESTFS_TMPDIR};
$g = Sys::Guestfs->new ();
die unless $g->get_tmpdir () eq $c;
die unless $g->get_cachedir () eq $b;

delete $ENV{LIBGUESTFS_CACHEDIR};
$g = Sys::Guestfs->new ();
die unless $g->get_tmpdir () eq $c;
die unless $g->get_cachedir () eq $c;

# Directories should be made absolute automatically.
delete $ENV{LIBGUESTFS_TMPDIR};
delete $ENV{LIBGUESTFS_CACHEDIR};
delete $ENV{TMPDIR};
$ENV{TMPDIR} = ".";
$g = Sys::Guestfs->new ();
my $pwd = `pwd`; chomp $pwd;
die unless $g->get_tmpdir () eq $pwd;
die unless $g->get_cachedir () eq $pwd;
