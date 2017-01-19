#!/usr/bin/env perl
# libguestfs
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

# This script lets you extract all the icons from a Windows guest.  We
# use this to locate the Windows logo in new releases of Windows (see
# lib/inspect-icon.c).
#
# Use it like this:
#   ./run ./contrib/windows-icons.pl /path/to/windows-disk.img

use strict;
use warnings;

use Sys::Guestfs;
use File::Temp qw{tempdir};

# Check that the tools we need are installed.
system ("wrestool --help >/dev/null 2>&1") == 0 or
    die "'wrestool' program is not installed\n";
#system ("icotool --help >/dev/null 2>&1") == 0 or
#    die "'icotool' program is not installed\n";

# Check user provided disk image argument(s).
if (@ARGV == 0) {
    print STDERR "usage: $0 /path/to/windows-disk.img\n";
    exit 1
}

# Assume libguestfs >= 1.19.32, because that means we don't
# have to worry about protocol limits in various calls.
my $g = Sys::Guestfs->new;
my %version = $g->version ();
unless ($version{minor} >= 20 ||
        $version{minor} >= 19 && $version{release} >= 32) {
    die "$0: version of libguestfs is too old, use >= 1.19.32\n"
}

# Open the disk image(s).
$g->add_drive ($_, readonly => 1) foreach @ARGV;
$g->launch ();

# Check it's Windows.
my @roots = $g->inspect_os ();
if (@roots == 0) {
    die "$0: no operating system found in disk image\n"
}

my $root = $roots[0];

if ($g->inspect_get_type ($root) ne "windows") {
    die "$0: disk image is not Windows (type = ", $g->inspect_get_type ($root),
        ")\n"
}

# Mount it up.
my %mps = $g->inspect_get_mountpoints ($root);
my @mps = sort { length $a <=> length $b } (keys %mps);
for my $mp (@mps) {
    eval { $g->mount_ro ($mps{$mp}, $mp) };
    if ($@) {
        print "$@ (ignored)\n"
    }
}

# Create an output directory.
my $output = tempdir (CLEANUP => 0);
print "writing icons to $output\n";
chdir $output or die "chdir: $output: $!";

# Get a list of all files.
my @files = $g->find ("/");
@files = map { "/$_" } @files;

print "writing list of files to $output/files\n";
open FILES, ">files" or die "open: files: $!";
print FILES join("\n", @files) or die "write: files: $!";
close FILES or die "close: files: $!";

# Find all *.exe files.  (XXX Can other file types contain resources?)
my @exe_files = grep { $_ =~ /\.exe$/i && $g->is_file ($_) } @files;

foreach (@exe_files) {
    # Download each *.exe file.
    my $basename = $_;
    $basename =~ s{.*/}{};
    $g->download ($_, $basename);

    # Extract any icon (2) or group-icon (14) resources it may contain.
    system ("wrestool", "-x", "--type=2", "-o", "./", $basename);
    system ("wrestool", "-x", "--type=14", "-o", "./", $basename);

    unlink $basename;
}

# Find and download all other image files.
foreach (@files) {
    my $basename = $_;
    $basename =~ s{.*/}{};

    if ($g->is_file ($_) &&
        $basename =~ /\.(png|git|jpeg|jpg|bmp|ico)$/i) {
        $g->download ($_, $basename);
    }
}

$g->close;
