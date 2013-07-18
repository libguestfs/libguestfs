#!/usr/bin/perl -w
# Test guestfs_disk_* functions.
# Copyright (C) 2013 Red Hat Inc.
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

use File::Temp qw(tempdir);

use Sys::Guestfs;

# Bail on 32 bit perl.
if (~1 == 4294967294) {
    print "$0: test skipped because your perl is not 64 bits\n";
    exit 77;
}

$ENV{LC_ALL} = "C";

my $tmpdir = tempdir (CLEANUP => 1);
my $errors = 0;

my $g = Sys::Guestfs->new ();

my ($format, $size, $backing);
foreach $format ("raw", "qcow2") {
    foreach $size (1024, 1024*1024, 1024*1024*1024, 1024*1024*1024*1024) {
        foreach $backing (0, 1) {
            # Raw files can't have backing files.
            next if $format eq "raw" && $backing;

            my $filename = create_disk ($tmpdir, $format, $size, $backing);

            my $detected_format = $g->disk_format ($filename);
            if ($detected_format ne $format) {
                print_disk ($filename, $format, $size, $backing, \*STDERR);
                printf STDERR ("unexpected format: detected %s, expected %s\n",
                               $detected_format, $format);
                $errors++;
            }

            my $detected_size = $g->disk_virtual_size ($filename);
            if ($detected_size != $size) {
                print_disk ($filename, $format, $size, $backing, \*STDERR);
                printf STDERR ("unexpected size: detected %d, expected %d\n",
                               $detected_size, $size);
                $errors++;
            }

            my $detected_backing = $g->disk_has_backing_file ($filename);
            if ($detected_backing != $backing) {
                print_disk ($filename, $format, $size, $backing, \*STDERR);
                printf STDERR ("unexpected backing file: detected %d, expected %d\n",
                               $detected_backing, $backing);
                $errors++;
            }
        }
    }
}

# Check the negative cases too: file not found, file is a directory.
# Note that since anything can be a raw file, there's no way to test
# that this would fail for a non-disk-image.
eval { $g->disk_format ($tmpdir . "/nosuchfile") };
if (!$@) {
    print STDERR "expected non-existent file to fail, but it did not\n";
    $errors++;
}
if ($@ !~ /No such file/) {
    print STDERR "unexpected error from non-existent file: $@\n";
    $errors++;
}

my $testdir = $tmpdir . "/dir";
mkdir $testdir, 0755;
eval { $g->disk_format ($testdir) };
if (!$@) {
    print STDERR "expected directory fail, but it did not\n";
    $errors++;
}
if ($@ !~ /is a directory/) {
    print STDERR "unexpected error from directory: $@\n";
    $errors++;
}

#----------------------------------------------------------------------

my $unique = 0;
sub get_unique
{
    return $unique++;
}

sub create_disk
{
    my $tmpdir = shift;
    my $format = shift;
    my $size = shift;
    my $backing = shift;

    my $options;

    if ($backing) {
        my $backing_file = sprintf ("%s/b%d", $tmpdir, get_unique ());
        qemu_img_create ("raw", "", $backing_file, 1024*1024);
        $options = "backing_file=%s"
    }

    my $filename = sprintf ("%s/d%d", $tmpdir, get_unique ());
    qemu_img_create ($format, $options, $filename, $size);
    return $filename;
}

sub qemu_img_create
{
    my $format = shift;
    my $options = shift;
    my $filename = shift;
    my $size = shift;

    my @cmd = ("qemu-img", "create", "-f", $format);
    if (defined $options) {
        push @cmd, "-o", $options;
    }
    push @cmd, $filename;
    if (defined $size) {
        push @cmd, $size;
    }
    system (@cmd) == 0 or die "system ", join (" ", @cmd), " failed: $?"
}

sub print_disk
{
    my $filename = shift;
    my $format = shift;
    my $size = shift;
    my $backing = shift;
    my $io = shift;

    printf $io ("created disk %s: format=%s, size=%d, backing=%d\n",
                $filename, $format, $size, $backing);
}

exit ($errors == 0 ? 0 : 1);
