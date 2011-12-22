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

# Test guestfish list-md-devices command

set -e

output=$(
../../fish/guestfish <<EOF
# Add 2 empty disks
sparse md-test1.img 100M
sparse md-test2.img 100M
run

# list-md-devices should return nothing
list-md-devices

# Create a raid1 based on the 2 disks
md-create test "/dev/sda /dev/sdb" level:raid1
EOF
)

# Ensure list-md-devices above returned nothing
if [ ! -z "$output" ]; then
    echo "$0: error: output of list-md-devices with no MD devices did not match expected output"
    echo $output
    exit 1;
fi

# Ensure list-md-devices now returns the newly created md device
output=$(
../../fish/guestfish -a md-test1.img -a md-test2.img <<EOF
run
list-md-devices
EOF
)

if [ "$output" != "/dev/md127" ]; then
    echo "$0: error: output of list-md-devices did not match expected output"
    echo "$output"
    exit 1
fi

rm -f md-test1.img md-test2.img
