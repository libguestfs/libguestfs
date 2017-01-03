#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2014-2018 Red Hat Inc.
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

# Test virt-v2v -oa (sparse/preallocated) option.

set -e

$TEST_FUNCTIONS
skip_if_skipped
# No support for either network or qcow2.
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
f=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-oa-option.d
rm -rf $d
mkdir $d

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d -oa preallocated -of qcow2

# Test the disk is qcow2 format.
if [ "$(guestfish disk-format $d/windows-sda)" != qcow2 ]; then
    echo "$0: test failed: output is not qcow2"
    exit 1
fi

# Test the disk is fully allocated.
if [ "$(du -m $d/windows-sda | awk '{print $1}')" -lt 500 ]; then
    echo "$0: test failed: output is not preallocated"
    exit 1
fi

rm -r $d
