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

# Test guestfish list-filesystems command finds file system on partitioned
# md device and does't take into account md device itself (similar to as
# physical devices are skipped if they are partitioned)

set -e

$TEST_FUNCTIONS
skip_if_skipped

disk1=list-filesystems2-1.img
disk2=list-filesystems2-2.img

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

output=$(
guestfish <<EOF
# Add 2 empty disks
sparse $disk1 50M
sparse $disk2 50M
run

# Create a raid0 based on the 2 disks
md-create test "/dev/sda /dev/sdb" level:raid0

part-init /dev/md127 mbr
part-add /dev/md127 p 64 41023
part-add /dev/md127 p 41024 81983

# Create filesystems
mkfs ext3 /dev/md127p1
mkfs ext4 /dev/md127p2

list-filesystems
EOF
)

expected="/dev/md127p1: ext3
/dev/md127p2: ext4"

if [ "$output" != "$expected" ]; then
    echo "$0: error: actual output did not match expected output"
    echo -e "actual:\n$output"
    echo -e "expected:\n$expected"
    exit 1
fi

# cleanup() is called implicitly which cleans up everything
exit 0
