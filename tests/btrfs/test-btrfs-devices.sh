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

mkdir /foo
touch /foo/bar

btrfs-device-add "/dev/sdc1 /dev/sdd1" /
btrfs-device-delete "/dev/sda1 /dev/sdb1" /

EOF

rm -f test[1234].img
