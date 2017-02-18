#!/bin/bash -
# libguestfs virt-sparsify test script
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

set -e

$TEST_FUNCTIONS
skip_if_skipped
# UML does not support qcow2.
skip_if_backend uml

rm -f test-virt-sparsify-1.img test-virt-sparsify-2.img

# Create a filesystem, fill it with data, then delete the data.  Then
# prove that sparsifying it reduces the size of the final filesystem.

$VG guestfish \
    -N test-virt-sparsify-1.img=bootrootlv:/dev/VG/LV:ext2:ext4:400M:32M:gpt <<EOF
mount /dev/VG/LV /
mkdir /boot
mount /dev/sda1 /boot
fill 1 300M /big
fill 1 10M /boot/big
sync
rm /big
rm /boot/big
umount-all
EOF

$VG virt-sparsify --debug-gc --format raw test-virt-sparsify-1.img --convert qcow2 test-virt-sparsify-2.img

size_before=$(du -s test-virt-sparsify-1.img | awk '{print $1}')
size_after=$(du -s test-virt-sparsify-2.img | awk '{print $1}')

echo "test virt-sparsify: $size_before K -> $size_after K"

if [ $size_before -lt 310000 ]; then
    echo "test virt-sparsify: size_before ($size_before) too small"
    exit 1
fi

if [ $size_after -gt 15000 ]; then
    echo "test virt-sparsify: size_after ($size_after) too large"
    echo "sparsification failed"
    exit 1
fi

rm test-virt-sparsify-1.img test-virt-sparsify-2.img
