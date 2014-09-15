#!/bin/bash -
# libguestfs virt-resize 2.0 test script
# Copyright (C) 2010-2012 Red Hat Inc.
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

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support qcow2"
    exit 77
fi

# Test expanding.
#
# This exercises a number of interesting codepaths including resizing
# LV content, handling GPT, and using qcow2 as a target.

$VG guestfish \
    -N test-virt-resize-1.img=bootrootlv:/dev/VG/LV:ext2:ext4:400M:32M:gpt </dev/null

$VG guestfish \
    disk-create test-virt-resize-2.img qcow2 500M preallocation:metadata

$VG virt-resize -d --debug-gc \
    --expand /dev/sda2 \
    --lv-expand /dev/VG/LV \
    --format raw --output-format qcow2 \
    test-virt-resize-1.img test-virt-resize-2.img

# Test shrinking in a semi-realistic scenario.  Although the disk
# image created above contains no data, we will nevertheless use
# similar operations to ones that might be used by a real admin.

guestfish -a test-virt-resize-1.img <<EOF
run
resize2fs-size /dev/VG/LV 190M
lvresize /dev/VG/LV 190
pvresize-size /dev/sda2 200M
fsck ext4 /dev/VG/LV
EOF

rm -f test-virt-resize-2.img; guestfish sparse test-virt-resize-2.img 300M
$VG virt-resize -d --debug-gc \
    --shrink /dev/sda2 \
    --format raw --output-format raw \
    test-virt-resize-1.img test-virt-resize-2.img

rm test-virt-resize-1.img test-virt-resize-2.img
