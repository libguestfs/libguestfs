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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Test the discovery of relationships between LVM PVs, VGs and LVs.

use strict;
use warnings;

use Sys::Guestfs;

my $testimg = "test.img";

unlink $testimg;
open FILE, ">$testimg" or die "$testimg: $!";
truncate FILE, 256*1024*1024 or die "$testimg: truncate: $!";
close FILE or die "$testimg: $!";

my $g = Sys::Guestfs->new ();

#$g->set_verbose (1);
#$g->set_trace (1);

$g->add_drive_opts ($testimg, format => "raw");
$g->launch ();

# Create an arrangement of PVs, VGs and LVs.
$g->sfdiskM ("/dev/sda", [",127", "128,"]);

$g->pvcreate ("/dev/sda1");
$g->pvcreate ("/dev/sda2");
$g->vgcreate ("VG", ["/dev/sda1", "/dev/sda2"]);

$g->lvcreate ("LV1", "VG", 32);
$g->lvcreate ("LV2", "VG", 32);
$g->lvcreate ("LV3", "VG", 32);

# Now let's get the arrangement.
my @pvs = $g->pvs ();
my @lvs = $g->lvs ();

my %pvuuids;
foreach my $pv (@pvs) {
    my $uuid = $g->pvuuid ($pv);
    $pvuuids{$uuid} = $pv;
}
my %lvuuids;
foreach my $lv (@lvs) {
    my $uuid = $g->lvuuid ($lv);
    $lvuuids{$uuid} = $lv;
}

# In this case there is only one VG, called "VG", but in a real
# program you'd want to repeat these steps for each VG that you found.
my @pvuuids_in_VG = $g->vgpvuuids ("VG");
my @lvuuids_in_VG = $g->vglvuuids ("VG");

my @pvs_in_VG;
foreach my $uuid (@pvuuids_in_VG) {
    push @pvs_in_VG, $pvuuids{$uuid};
}
@pvs_in_VG = sort @pvs_in_VG;

my @lvs_in_VG;
foreach my $uuid (@lvuuids_in_VG) {
    push @lvs_in_VG, $lvuuids{$uuid};
}
@lvs_in_VG = sort @lvs_in_VG;

unless (@pvs_in_VG == 2 &&
        $pvs_in_VG[0] eq "/dev/vda1" && $pvs_in_VG[1] eq "/dev/vda2") {
    die "unexpected set of PVs for volume group VG: [",
      join (", ", @pvs_in_VG), "]\n"
}

unless (@lvs_in_VG == 3 &&
        $lvs_in_VG[0] eq "/dev/VG/LV1" &&
        $lvs_in_VG[1] eq "/dev/VG/LV2" &&
        $lvs_in_VG[2] eq "/dev/VG/LV3") {
    die "unexpected set of LVs for volume group VG: [",
      join (", ", @lvs_in_VG), "]\n"
}

undef $g;

unlink $testimg or die "$testimg: unlink: $!";
