#!/bin/bash -
# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=1011907
# https://bugzilla.redhat.com/show_bug.cgi?id=1165785
# i.e., mount-loop option, which means correct startup sequence and creation
# of base devices (like /dev/loop-control for loopback setup)

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f rhbz1011907-1165785-loop.img rhbz1011907-1165785.img

qemu-img create rhbz1011907-1165785-loop.img 100M
qemu-img create rhbz1011907-1165785.img 300M

guestfish --format=raw -a rhbz1011907-1165785-loop.img <<EOF
run
part-disk /dev/sda mbr
mkfs ext3 /dev/sda
mount /dev/sda /
touch /in-loop
EOF

output=$(
guestfish --format=raw -a rhbz1011907-1165785.img <<EOF
run
part-disk /dev/sda mbr
mkfs ext3 /dev/sda1
mount /dev/sda1 /
upload rhbz1011907-1165785-loop.img /rhbz1011907-1165785-loop.img
mkmountpoint /loop
mount-loop /rhbz1011907-1165785-loop.img /loop/
is-file /loop/in-loop
EOF
)

if [ "$output" != \
"true" ]; then
    echo "$0: error: output of guestfish did not match expected output"
    echo "$output"
    exit 1
fi

rm rhbz1011907-1165785-loop.img rhbz1011907-1165785.img
