#!/usr/bin/perl -w
# libguestfs
# Copyright (C) 2018 Red Hat Inc.
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

# From painful experience we know that changes to the kernel can
# suddenly change the maximum number of disks we can add to the
# appliance.  This script uses a simple binary search to find the
# current maximum.
#
# To test different kernels you may want to do:
# rm -rf /var/tmp/.guestfs-*
# export SUPERMIN_KERNEL=/boot/vmlinuz-...
# export SUPERMIN_MODULES=/lib/modules/...
# ./max-disks.pl
#
# See also:
# https://bugzilla.redhat.com/show_bug.cgi?id=1478201#c4

use strict;
use Sys::Guestfs;

$| = 1;

my $low = 1;
my $high = 2048;  # Will never test higher than this.
my $mid = 1024;

# Get the kernel under test.
my $g = Sys::Guestfs->new ();
$g->launch ();
my %kernel = $g->utsname;
$g->close ();

sub test_mid
{
    my ($ret, %k);

    eval {
        my $g = Sys::Guestfs->new ();
        for (my $i = 0; $i < $mid; ++$i) {
            $g->add_drive_scratch (1024*1024);
        }
        $g->launch ();
        %k = $g->utsname;
        $g->shutdown ();
    };
    if ($@) {
        printf ("%d => bad\n", $mid);
        $ret = 0;
    }
    else {
        printf ("%d => good\n", $mid);
        $ret = 1;
    }

    die "kernel version changed during test!\n"
        if exists $k{uts_release} && $k{uts_release} ne $kernel{uts_release};

    return $ret;
}

for (;;) {
    if (test_mid ()) {
        # good, so try higher
        $low = $mid;
    }
    else {
        # bad, so try lower
        $high = $mid;
    }
    $mid = int (($high+$low) / 2);
    if ($mid == $high || $mid == $low) {
        printf("kernel: %s %s (%s)\n",
               $kernel{uts_sysname}, $kernel{uts_release},
               $kernel{uts_machine});
        # +1 because of the appliance disk.
        printf ("max disks = %d\n", $mid+1);
        exit 0;
    }
}
