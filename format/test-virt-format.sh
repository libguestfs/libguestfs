#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

# Test virt-format command.

set -e

if [ -n "$SKIP_TEST_VIRT_FORMAT_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

rm -f test-virt-format.img

$VG guestfish -N test-virt-format.img=bootrootlv exit

$VG virt-format --filesystem=ext3 --format=raw -a test-virt-format.img

if [ "$($VG virt-filesystems --format=raw -a test-virt-format.img)" != "/dev/sda1" ]; then
    echo "$0: unexpected output after using virt-format"
    exit 1
fi

rm test-virt-format.img
