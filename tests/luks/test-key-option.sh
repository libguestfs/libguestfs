#!/bin/bash -
# libguestfs
# Copyright (C) 2019 Red Hat Inc.
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

# Test the --key option.  It is handled by common code so we only need
# to test one tool (guestfish).

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available luks

d=test-key-option.img
rm -f $d

# Create a test disk
guestfish --keys-from-stdin <<EOF
sparse $d 1G
run
part-disk /dev/sda mbr

pvcreate /dev/sda1
vgcreate VG /dev/sda1

# Create some LVs which will contain the LUKS devices.
lvcreate LV1 VG 64
lvcreate LV2 VG 64
lvcreate LV3 VG 64
lvcreate LV4 VG 64

# Create the LUKS devices, give each a different key.
luks-format /dev/VG/LV1 0
keylv1
luks-format /dev/VG/LV2 0
keylv2
luks-format /dev/VG/LV3 0
keylv3
luks-format /dev/VG/LV4 0
keylv4
EOF

# Try to open the devices from the guestfish command line.
guestfish -a $d \
          --key /dev/VG/LV1:key:keylv1 \
          --key /dev/VG/LV2:key:badkey --key /dev/VG/LV2:key:keylv2 \
          run : echo-daemon ok
#          --key :key:keylv3
#          --key :key:keylv4

rm $d
