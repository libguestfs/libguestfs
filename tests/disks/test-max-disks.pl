#!/usr/bin/perl
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

# Test adding maximum number of disks to the guest.

use strict;
use warnings;

use Sys::Guestfs;

my $errors = 0;

my $g = Sys::Guestfs->new ();

my $max_disks = $g->max_disks ();
printf "max_disks is %d\n", $max_disks;

# Create large number of disks.
my ($name, $i, $j);
for ($i = 0; $i < $max_disks; ++$i) {
    $g->add_drive_scratch (1024*1024);
}

$g->launch ();

# Check the disks were added.
my @devices = $g->list_devices ();
if (@devices != $max_disks) {
    print STDERR "$0: incorrect number of devices returned by \$g->list_devices:\n";
    print STDERR "$0: \@devices = ", join (" ", @devices), "\n";
    $errors++;
}

for ($i = 0; $i < $max_disks; ++$i) {
    my $expected = drive_name ($i);
    unless ($devices[$i] =~ m{/dev/[abce-ln-z]+d$expected$}) {
        print STDERR "$0: incorrect device name at index $i: ",
            "expected /dev/sd$expected, but got $devices[$i]\n";
        $errors++;
    }
}

# Check device_index.
for ($i = 0; $i < $max_disks; ++$i) {
    if ($i != $g->device_index ($devices[$i])) {
        print STDERR "$0: incorrect device index for $devices[$i]\n";
        $errors++;
    }
}

# Put some data on each disk to check they are mountable, writable etc.
for ($i = 0; $i < $max_disks; ++$i) {
    my $dev = $devices[$i];
    $g->mkmountpoint ("/mp$i");

    # To save time in the test, add 15 partitions to the first disk
    # and last disks only, and 1 partition to every other disk.  Note
    # that 15 partitions is the max allowed by virtio-blk.
    my $part;
    if ($i == 0 || $i == $max_disks-1) {
        $g->part_init ($dev, "gpt");
        for ($j = 1; $j <= 14; ++$j) {
            $g->part_add ($dev, "p", 64*$j, 64*$j+63);
        }
        $g->part_add ($dev, "p", 64*15, -64);
        $part = $dev . "15";
    }
    else {
        $g->part_disk ($dev, "mbr");
        $part = $dev . "1";
    }
    $g->mkfs ("ext2", "$part");
    $g->mount ("$part", "/mp$i");
    $g->write ("/mp$i/disk$i", "This is disk #$i.\n");
}

for ($i = 0; $i < $max_disks; ++$i) {
    if ($g->cat ("/mp$i/disk$i") ne "This is disk #$i.\n") {
        print STDERR "$0: unexpected content in file /mp$i/disk$i\n";
        $errors++;
    }
}

# Enumerate and check partition names.
my @partitions = $g->list_partitions ();
if (@partitions != $max_disks + 14*2) {
    print STDERR "$0: incorrect number of partitions returned by \$g->list_partitions:\n";
    print STDERR "$0: \@partitions = ", join (" ", @partitions), "\n";
    $errors++;
}

for ($i = 0, $j = 0; $i < $max_disks; ++$i) {
    my $expected = drive_name ($i);
    if ($i == 0 || $i == $max_disks-1) {
        unless ($partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}1$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}2$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}3$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}4$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}5$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}6$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}7$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}8$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}9$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}10$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}11$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}12$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}13$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}14$} &&
                $partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}15$}) {
            print STDERR "$0: incorrect partition name at index $i\n";
            $errors++;
        }
    } else {
        unless ($partitions[$j++] =~ m{/dev/[abce-ln-z]+d${expected}1$}) {
            print STDERR "$0: incorrect partition name at index $i\n";
            $errors++;
        }
    }
}

$g->shutdown ();
$g->close ();

exit ($errors == 0 ? 0 : 1);

sub drive_name
{
    my $index = shift;
    my $prefix = "";
    if ($index >= 26) {
        $prefix = drive_name ($index/26 - 1);
    }
    $index %= 26;
    return $prefix . chr (97 + $index);
}
