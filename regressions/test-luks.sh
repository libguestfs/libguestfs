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

# Test LUKS device creation, opening, key slots.

set -e

[ -n "$SKIP_TEST_LUKS_SH" ] && {
    echo "test-luks.sh skipped (environment variable set)"
    exit 0
}

rm -f test1.img

../fish/guestfish --keys-from-stdin <<EOF
sparse test1.img 1G
run
part-disk /dev/sda mbr

# Create LUKS device with key "key0" in slot 0.
luks-format /dev/sda1 0
key0

# Open the device.
luks-open /dev/sda1 lukstest
key0

# Put some LVM structures on the encrypted device.
pvcreate /dev/mapper/lukstest
vgcreate VG /dev/mapper/lukstest
lvcreate LV1 VG 64
lvcreate LV2 VG 64
vg-activate-all false

# Close the device.
luks-close /dev/mapper/lukstest

# Add keys in other slots.
luks-add-key /dev/sda1 1
key0
key1
luks-add-key /dev/sda1 2
key1
key2
luks-add-key /dev/sda1 3
key2
key3

# Check we can open the device with one of the new keys.
luks-open /dev/sda1 lukstest
key1
luks-close /dev/mapper/lukstest
luks-open /dev/sda1 lukstest
key3
luks-close /dev/mapper/lukstest

# Remove a key.
luks-kill-slot /dev/sda1 1
key0

# This is expected to fail.
-luks-open /dev/sda1 lukstest
key1

# Replace a key slot.
luks-kill-slot /dev/sda1 3
key2
luks-add-key /dev/sda1 3
key2
newkey3

luks-open /dev/sda1 lukstest
newkey3
luks-close /dev/mapper/lukstest

EOF

rm -f test1.img
