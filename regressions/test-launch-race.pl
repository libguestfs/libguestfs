#!/usr/bin/perl
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Test that 2 simultaneous launches in a clean cache directory will both succeed

use strict;
use warnings;

use File::Temp qw(tempdir);
use POSIX;

use Sys::Guestfs;

# Use a temporary TMPDIR to ensure it's clean
my $tmpdir = tempdir (CLEANUP => 1);
$ENV{TMPDIR} = $tmpdir;

my $testimg = $tmpdir.'/test.img';
system ("touch $testimg");

my $pid = fork();
die ("fork failed: $!") if ($pid < 0);

if ($pid == 0) {
  my $g = Sys::Guestfs->new ();
  $g->add_drive ($testimg);
  $g->launch ();
  _exit (0);
}

my $g = Sys::Guestfs->new ();
$g->add_drive ($testimg);
$g->launch ();
$g = undef;

waitpid ($pid, 0) or die ("waitpid: $!");
die ("child failed") unless ($? == 0);

# Check that only 1 temporary cache directory was created
my $dh;
opendir ($dh, $tmpdir) or die ("Failed to open $tmpdir: $!");
my @cachedirs = grep { /^guestfs\./ } readdir ($dh);
closedir ($dh) or die ("Failed to close $tmpdir: $!");

my $ncachedirs = scalar(@cachedirs);
die ("Expected 1 cachedir, found $ncachedirs") unless ($ncachedirs == 1);
