#!/bin/bash -
# libguestfs
# Copyright (C) 2009-2017 Red Hat Inc.
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
skip_unless_phony_guest fedora.img

# Run virt-list-filesystems.
# Only columns 1 & 2 are guaranteed, we may add more in future.
if [ "$($srcdir/virt-list-filesystems \
            --format=raw -l \
            $top_builddir/test-data/phony-guests/fedora.img |
        sort | awk '{print $1 $2}')" \
    != \
"/dev/VG/LV1ext2
/dev/VG/LV2ext2
/dev/VG/LV3ext2
/dev/VG/Rootext2
/dev/sda1ext2" ]; then
    echo "$0: error: unexpected output from virt-list-filesystems"
    exit 1
fi
