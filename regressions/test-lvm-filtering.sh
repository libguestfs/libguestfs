#!/bin/bash -
# libguestfs
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

# Test LVM device filtering.

set -e

rm -f test1.img test2.img

actual=$(../fish/guestfish <<'EOF'
sparse test1.img 1G
sparse test2.img 1G

run

part-disk /dev/sda mbr
part-disk /dev/sdb mbr

pvcreate /dev/sda1
pvcreate /dev/sdb1

vgcreate VG1 /dev/sda1
vgcreate VG2 /dev/sdb1

# Should see VG1 and VG2
vgs

# Should see just VG1
lvm-set-filter /dev/sda
vgs
lvm-set-filter /dev/sda1
vgs

# Should see just VG2
lvm-set-filter /dev/sdb
vgs
lvm-set-filter /dev/sdb1
vgs

# Should see VG1 and VG2
lvm-set-filter "/dev/sda /dev/sdb"
vgs
lvm-set-filter "/dev/sda1 /dev/sdb1"
vgs
lvm-set-filter "/dev/sda /dev/sdb1"
vgs
lvm-set-filter "/dev/sda1 /dev/sdb"
vgs
lvm-clear-filter
vgs
EOF
)

expected="VG1
VG2
VG1
VG1
VG2
VG2
VG1
VG2
VG1
VG2
VG1
VG2
VG1
VG2
VG1
VG2"

rm -f test1.img test2.img

if [ "$actual" != "$expected" ]; then
    echo "LVM filter test failed.  Actual output was:"
    echo "$actual"
    exit 1
fi
