#!/bin/bash -
# libguestfs virt-sparsify --in-place test script
# Copyright (C) 2011-2016 Red Hat Inc.
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

export LANG=C
set -e

if [ -n "$SKIP_TEST_VIRT_SPARSIFY_IN_PLACE_SH" ]; then
    echo "$0: skipping test (environment variable set)"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support discard"
    exit 77
fi

rm -f test-virt-sparsify-in-place.img

# Create a filesystem, fill it with data, then delete the data.  Then
# prove that sparsifying it reduces the size of the final filesystem.

$VG guestfish \
    -N test-virt-sparsify-in-place.img=bootrootlv:/dev/VG/LV:ext4:ext4:400M:32M:gpt <<EOF
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

size_before=$(du -s test-virt-sparsify-in-place.img | awk '{print $1}')

$VG virt-sparsify --debug-gc --in-place --format raw test-virt-sparsify-in-place.img || {
    if [ "$?" -eq 3 ]; then
        rm test-virt-sparsify-in-place.img
        echo "$0: discard not supported in virt-sparsify"
        exit 77
    fi
    exit 1
}

size_after=$(du -s test-virt-sparsify-in-place.img | awk '{print $1}')

echo "test virt-sparsify: $size_before K -> $size_after K"

if [ $size_before -lt 310000 ]; then
    echo "test virt-sparsify --in-place: size_before ($size_before) too small"
    exit 1
fi

# The space we're expecting to recover is 300 + 10 MB, so as long as
# size_before - size_after > 300000 it shows we have recovered the
# majority of the file space and sparsification is working.  (RHBZ#1079210)

if [ $((size_before-size_after)) -le 300000 ]; then
    echo "test virt-sparsify --in-place: size_after ($size_after) too large"
    echo "sparsification failed"
    exit 1
fi

rm test-virt-sparsify-in-place.img
