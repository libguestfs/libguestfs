#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2017 Red Hat Inc.
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

# Test -i ova option.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"
export VIRTIO_WIN="$top_srcdir/test-data/fake-virtio-win"

rm -f test-v2v-i-vmx-*.actual

for i in 1 2 3 4; do
    $VG virt-v2v --debug-gc \
        -i vmx test-v2v-i-vmx-$i.vmx \
        --print-source > test-v2v-i-vmx-$i.actual

    # Normalize the print-source output.
    mv test-v2v-i-vmx-$i.actual test-v2v-i-vmx-$i.actual.old
    sed \
        -e "s,.*Opening the source.*,," \
        -e "s,$(pwd),," \
        < test-v2v-i-vmx-$i.actual.old > test-v2v-i-vmx-$i.actual
    rm test-v2v-i-vmx-$i.actual.old

    # Check the output.
    diff -u test-v2v-i-vmx-$i.expected test-v2v-i-vmx-$i.actual
done

rm test-v2v-i-vmx-*.actual
