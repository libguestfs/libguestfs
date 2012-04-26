#!/bin/bash -
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

# Test btrfs adding/removing devices.
#
# This test is intended to try and abuse btrfs by writing lots of data
# to the disk, then instructing btrfs to move the data between
# devices.

set -e

# XXX Not a very good test.
if ! btrfs --help >/dev/null 2>&1; then
    echo "$0: test skipped because no 'btrfs' utility"
    exit 0
fi

rm -f test[1234].img

../../fish/guestfish <<EOF
# Add four empty disks
sparse test1.img 1G
sparse test2.img 1G
sparse test3.img 1G
sparse test4.img 1G
run

part-disk /dev/sda mbr
part-disk /dev/sdb mbr
part-disk /dev/sdc mbr
part-disk /dev/sdd mbr

mkfs-btrfs "/dev/sda1 /dev/sdb1"
mount /dev/sda1 /

mkdir /data1
txz-in ../data/filesanddirs-10M.tar.xz /data1

# In btrfs-progs 0.19, a test was added which prevents us from
# deleting the mount device (/dev/sda1) although that restriction
# isn't necessary.  RHBZ#816346.  If/when this is fixed, we could
# delete and re-add /dev/sda1 below.

btrfs-device-add "/dev/sdc1 /dev/sdd1" /
btrfs-device-delete "/dev/sdb1" /
btrfs-device-add "/dev/sdb1" /
btrfs-device-delete "/dev/sdc1 /dev/sdd1" /

mkdir /data2
txz-in ../data/filesanddirs-10M.tar.xz /data2

btrfs-device-add "/dev/sdc1 /dev/sdd1" /
btrfs-device-delete "/dev/sdb1" /
btrfs-device-add "/dev/sdb1" /
btrfs-device-delete "/dev/sdc1 /dev/sdd1" /

mkdir /data3
txz-in ../data/filesanddirs-10M.tar.xz /data3

btrfs-device-add "/dev/sdc1 /dev/sdd1" /
btrfs-device-delete "/dev/sdb1" /
btrfs-device-add "/dev/sdb1" /
btrfs-device-delete "/dev/sdc1 /dev/sdd1" /

mkdir /data4
txz-in ../data/filesanddirs-10M.tar.xz /data4

btrfs-device-add "/dev/sdc1 /dev/sdd1" /
btrfs-device-delete "/dev/sdb1" /
btrfs-device-add "/dev/sdb1" /
btrfs-device-delete "/dev/sdc1 /dev/sdd1" /

EOF

rm -f test[1234].img
