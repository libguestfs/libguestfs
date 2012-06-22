#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# Test guestfish list-mddevices command

set -e

if [ -n "$SKIP_TEST_LIST_FILESYSTEMS_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 0
fi

rm -f test.output

# Create 2 disks partitioned as:
# sda1: 20M ext3
# sda2: 20M MD (md127)
#
# sdb1: 20M PV (vg0)
# sdb2: 20M MD (md127)
#
# md127 : 20M ext4
# vg0 : 16M LV (lv0)
# lv0 : 16M vfat
../../fish/guestfish <<EOF | sed s,/dev/vd,/dev/sd,g > test.output
# Add 2 empty disks
sparse fs-test1.img 50M
sparse fs-test2.img 50M
run

part-init /dev/sda mbr
part-add /dev/sda p 64 41023
part-add /dev/sda p 41024 81983
part-init /dev/sdb mbr
part-add /dev/sdb p 64 41023
part-add /dev/sdb p 41024 81983

# Create vg0 and lv0 on /dev/sdb1
pvcreate /dev/sdb1
vgcreate vg0 /dev/sdb1
lvcreate lv0 vg0 16

# Create an md device from sda2 and sdb2
md-create test "/dev/sda2 /dev/sdb2" level:raid1

# Create filesystems
mkfs ext3 /dev/sda1
mkfs ext4 /dev/md127
mkfs vfat /dev/vg0/lv0

list-filesystems
EOF

expected="/dev/sda1: ext3
/dev/md127: ext4
/dev/vg0/lv0: vfat"

# Check the output of list-filesystems
if [ "$(cat test.output)" != "$expected" ]; then
    echo "$0: error: output of list-filesystems did not match expected output"
    printf "%s\n" "$output"
    exit 1;
fi


rm -f fs-test1.img fs-test2.img test.output
