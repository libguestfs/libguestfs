#!/usr/bin/perl -w
# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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

# Test that the daemon starts and stops.

use strict;
use warnings;

use File::Temp qw/tempdir/;

require 'captive-daemon.pm';

# Set $PATH to include directory that will have phony 'btrfs' binary.
my $bindir = tempdir (CLEANUP => 1);
$ENV{PATH} = $bindir . ":" . $ENV{PATH};

sub set_btrfs_output {
    my $output = shift;
    open BTRFS, ">$bindir/btrfs" or die "$bindir/btrfs: $!";
    print BTRFS "#!/bin/sh\n";
    print BTRFS "cat << '__EOF'\n";
    print BTRFS $output;
    print BTRFS "__EOF\n";
    close BTRFS;
    chmod 0755, "$bindir/btrfs" or die "chmod: $bindir/btrfs: $!";
}

sub tests {
    my $g = shift;

    # Test btrfs_subvolume_list.
    my $output = <<EOF;
ID 256 gen 30 top level 5 path test1
ID 257 gen 30 top level 5 path dir/test2
ID 258 gen 30 top level 5 path test3
EOF
    set_btrfs_output ($output);
    my @r = $g->btrfs_subvolume_list ("/");
    die unless @r == 3;
    die unless $r[0]->{btrfssubvolume_id} == 256;
    die unless $r[0]->{btrfssubvolume_top_level_id} == 5;
    die unless $r[0]->{btrfssubvolume_path} eq "test1";
    die unless $r[1]->{btrfssubvolume_id} == 257;
    die unless $r[1]->{btrfssubvolume_top_level_id} == 5;
    die unless $r[1]->{btrfssubvolume_path} eq "dir/test2";
    die unless $r[2]->{btrfssubvolume_id} == 258;
    die unless $r[2]->{btrfssubvolume_top_level_id} == 5;
    die unless $r[2]->{btrfssubvolume_path} eq "test3";

    # Return true to indicate the test succeeded.
    1;
}

CaptiveDaemon::run_tests ()
