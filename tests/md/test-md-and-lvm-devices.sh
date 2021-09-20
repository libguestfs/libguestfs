#!/bin/bash -
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

# Test guestfish finds:
# 1. md device created from physical block device and LV,
# 2. md device created from LVs
# 3. LV created on md device
#
# raid0 is used for md device because it is inoperable if one of its components
# is inaccessible so it is easy observable that md device is missing (raid1 in
# this case will be operable but in degraded state).

set -e

$TEST_FUNCTIONS
skip_if_skipped

disk1=md-and-lvm-devices-1.img
disk2=md-and-lvm-devices-2.img

rm -f $disk1 $disk2

# Clean up if the script is killed or exits early
cleanup ()
{
    status=$?
    set +e

    # Don't delete the output files if non-zero exit
    if [ "$status" -eq 0 ]; then rm -f $disk1 $disk2; fi

    exit $status
}
trap cleanup INT QUIT TERM EXIT

# Create 2 disks partitioned as:
# sda1: 20M MD (md127)
# sda2: 20M PV (vg1)
# sda3: 20M MD (md125)
#
# sdb1: 24M PV (vg0) [*]
# sdb2: 20M PV (vg2)
# sdb3: 20M MD (md125)
#
# lv0   : LV (vg0)
# lv1   : LV (vg1)
# lv2   : LV (vg2)
# md127 : md (sda1, lv0)
# md126 : md (lv1, lv2)
# md125 : md (sda3, sdb3)
# vg3   : VG (md125)
# lv3   : LV (vg3)
#
# [*] The reason for making sdb1 4M larger than sda1 is that the LVM metadata
# will consume one 4MB extent, and we need lv0 to offer exactly as much space
# as sda1 does, for combining them in md127. Refer to RHBZ#2005485.

guestfish <<EOF
# Add 2 empty disks
sparse $disk1 100M
sparse $disk2 100M
run

# Partition disks
part-init /dev/sda mbr
part-add /dev/sda p 64 41023
part-add /dev/sda p 41024 81983
part-add /dev/sda p 81984 122943
part-init /dev/sdb mbr
part-add /dev/sdb p 64 49215
part-add /dev/sdb p 49216 90175
part-add /dev/sdb p 90176 131135

# Create volume group and logical volume on sdb1
pvcreate /dev/sdb1
vgcreate vg0 /dev/sdb1
lvcreate-free lv0 vg0 100

# Create md from sda1 and vg0/lv0
md-create md-sda1-lv0 "/dev/sda1 /dev/vg0/lv0" level:raid0

# Create volume group and logical volume on sda2
pvcreate /dev/sda2
vgcreate vg1 /dev/sda2
lvcreate-free lv1 vg1 100

# Create volume group and logical volume on sdb2
pvcreate /dev/sdb2
vgcreate vg2 /dev/sdb2
lvcreate-free lv2 vg2 100

# Create md from vg1/lv1 and vg2/lv2
md-create md-lv1-lv2 "/dev/vg1/lv1 /dev/vg2/lv2" level:raid0

# Create md from sda3 and sdb3
md-create md-sda3-sdb3 "/dev/sda3 /dev/sdb3" level:raid0

# Create volume group and logical volume on md125 (last created md)
pvcreate /dev/md125
vgcreate vg3 /dev/md125
lvcreate-free lv3 vg3 100
EOF

# Ensure list-md-devices now returns all created md devices
# and lvs returns all created logical volumes.
output=$(
guestfish --format=raw -a $disk1 --format=raw -a $disk2 <<EOF
run
list-md-devices
lvs
EOF
)

expected="/dev/md125
/dev/md126
/dev/md127
/dev/vg0/lv0
/dev/vg1/lv1
/dev/vg2/lv2
/dev/vg3/lv3"

if [ "$output" != "$expected" ]; then
    echo "$0: error: actual output did not match expected output"
    echo -e "actual:\n$output"
    echo -e "expected:\n$expected"
    exit 1
fi

# cleanup() is called implicitly which cleans up everything
exit 0
