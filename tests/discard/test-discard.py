#!/usr/bin/env perl
# Copyright (C) 2014 Red Hat Inc.
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

# Test that -o discard works.

use strict;
use warnings;

use Sys::Guestfs;

# Since we read error messages, we want to ensure they are printed
# in English, hence:
$ENV{"LANG"} = "C";

$| = 1;

if ($ENV{SKIP_TEST_DISCARD_PL}) {
    print "$0: skipped test because environment variable is set\n";
    exit 77;
}

my $g = Sys::Guestfs->new ();

# Discard is only supported when using qemu.
if ($g->get_backend () ne "libvirt" &&
    $g->get_backend () !~ /^libvirt:/ &&
    $g->get_backend () ne "direct") {
    print "$0: skipped test because discard is only supported when using qemu\n";
    exit 77;
}

# You can set this to "raw" or "qcow2".
my $format = "raw";

# Size needs to be at least 32 MB so we can fit an ext4 filesystem on it.
my $size = 64 * 1024 * 1024;

my $disk;
my @args;
if ($format eq "raw") {
    $disk = "test-discard.img";
    @args = ( preallocation => "sparse" );
} elsif ($format eq "qcow2") {
    $disk = "test-discard.qcow2";
    @args = ( preallocation => "off", compat => "1.1" );
} else {
    die "$0: invalid disk format: $format\n";
}

# Create a disk and add it with discard enabled.  This is allowed to
# fail, eg because qemu is too old, but libguestfs must tell us that
# it failed (since we're using 'enable', not 'besteffort').
$g->disk_create ($disk, $format, $size, @args);
END { unlink ($disk); };

eval {
    $g->add_drive ($disk, format => $format, readonly => 0, discard => "enable");
    $g->launch ();
};
if ($@) {
    if ($@ =~ /discard cannot be enabled on this drive/) {
        # This is OK.  Libguestfs says it's not possible to enable
        # discard on this drive (eg. because qemu is too old).  Print
        # the reason and skip the test.
        print "$0: skipped test: $@\n";
        exit 77;
    }
    die # propagate the unexpected error
}

# At this point we've got a disk which claims to support discard.
# Let's test that theory.

my $orig_size = (stat ($disk))[12];
print "original size:\t$orig_size (blocks)\n";
#system "du -sh $disk";

# Write a filesystem onto the disk and fill it with data.

$g->mkfs ("ext4", "/dev/sda");
$g->mount_options ("discard", "/dev/sda", "/");
$g->fill (33, 10000000, "/data");
$g->sync ();

my $full_size = (stat ($disk))[12];
print "full size:\t$full_size (blocks)\n";
#system "du -sh $disk";

die "$0: surprising result: full size <= original size\n"
    if $full_size <= $orig_size;

# Remove the file and check the filesystem is trimmed automatically.

$g->rm ("/data");
$g->shutdown ();
$g->close ();

my $trimmed_size = (stat ($disk))[12];
print "trimmed size:\t$trimmed_size (blocks)\n";
#system "du -sh $disk";

die "$0: looks like the -o discard mount option did not work\n"
    if $full_size - $trimmed_size < 1000;
