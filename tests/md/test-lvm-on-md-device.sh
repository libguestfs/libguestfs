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

# Test guestfish finds logical volume (LV) created on md device

set -e

$TEST_FUNCTIONS
skip_if_skipped

disk1=lvm-on-md-devices-1.img
disk2=lvm-on-md-devices-2.img

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

guestfish <<EOF
# Add 2 empty disks
sparse $disk1 100M
sparse $disk2 100M
run

# Create a raid0 based on the 2 disks
md-create test "/dev/sda /dev/sdb" level:raid0

# Create volume group and logical volume on md device
pvcreate /dev/md127
vgcreate vg0 /dev/md127
lvcreate-free lv0 vg0 100
EOF

# Ensure list-md-devices now returns the newly created md device
# and lvs returns newly created logical volume.
output=$(
guestfish --format=raw -a $disk1 --format=raw -a $disk2 <<EOF
run
list-md-devices
lvs
EOF
)

expected="/dev/md127
/dev/vg0/lv0"

if [ "$output" != "$expected" ]; then
    echo "$0: error: actual output did not match expected output"
    echo -e "actual:\n$output"
    echo -e "expected:\n$expected"
    exit 1
fi

# cleanup() is called implicitly which cleans up everything
exit 0