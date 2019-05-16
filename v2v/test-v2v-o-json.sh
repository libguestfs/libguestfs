#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2019 Red Hat Inc.
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

# Test -o json.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img
skip_unless jq --version

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

guestname=windows

d=test-v2v-o-json.d
rm -rf $d
mkdir $d

json=$d/$guestname.json
disk=$d/$guestname-sda

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o json -os $d -on $guestname

# Test the disk was created.
test -f $disk

# Test the JSON.
test x$(jq -r '.name' $json) = xwindows
test x$(jq -r '.inspect.type' $json) = xwindows
test x$(jq -r '.inspect.distro' $json) = xwindows
test x$(jq -r '.inspect.osinfo' $json) = xwin7
test $(jq -r '.disks | length' $json) -eq 1
test $(jq -r '.disks[0].file' $json) = $(realpath $disk)
test $(jq -r '.nics | length' $json) -eq 1
test $(jq -r '.removables | length' $json) -eq 0

# Clean up.
rm -r $d
