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

# Test LUKS devices appear in the output of list-dm-devices.

set -e

[ -n "$SKIP_TEST_LUKS_SH" ] && {
    echo "test-luks-list.sh skipped (environment variable set)"
    exit 77
}

rm -f test1.img test.output

../../fish/guestfish --keys-from-stdin > test.output <<'EOF'
sparse test1.img 1G
run
part-init /dev/sda mbr
part-add /dev/sda p 64 1048575
part-add /dev/sda p 1048576 -64

# Create LUKS device with key "key0" in slot 0.
luks-format /dev/sda1 0
key0

# Create some unrelated LVs.
pvcreate /dev/sda2
vgcreate VG /dev/sda2
lvcreate LV1 /dev/VG 100
lvcreate LV2 /dev/VG 200
lvcreate LV3 /dev/VG 100

# Open the device as 'lukstest'.
luks-open /dev/sda1 lukstest
key0

# List devices, '/dev/mapper/lukstest' should appear.
echo test 1
list-dm-devices

# Close the device.
luks-close /dev/mapper/lukstest

# List devices, '/dev/mapper/lukstest' should not appear.
echo test 2
list-dm-devices

# Open the device again.
luks-open /dev/sda1 lukstest
key0

# Check no LVs appear in list-dm-devices output.
echo test 3
list-dm-devices

# Check LUKS device doesn't appear in any of the other lists.
echo test 4
list-devices | sed 's,^/dev/[hv]d,/dev/sd,'
echo test 5
list-partitions | sed 's,^/dev/[hv]d,/dev/sd,'
echo test 6
lvs
echo test 7
vgs
echo test 8
pvs | sed 's,^/dev/[hv]d,/dev/sd,'

EOF

# Expected vs actual output.
if [ "$(cat test.output)" != "\
test 1
/dev/mapper/lukstest
test 2
test 3
/dev/mapper/lukstest
test 4
/dev/sda
test 5
/dev/sda1
/dev/sda2
test 6
/dev/VG/LV1
/dev/VG/LV2
/dev/VG/LV3
test 7
VG
test 8
/dev/sda2" ]; then
    echo "test-luks-list.sh: Unexpected output from test:"
    cat test.output
    echo "[end of output]"
    exit 1
fi

rm -f test1.img test.output
