#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2014 Red Hat Inc.
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

# Test --network and --bridge parameters.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_NETWORKS_AND_BRIDGES_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

abs_builddir="$(pwd)"
libvirt_uri="test://$abs_builddir/test-v2v-networks-and-bridges.xml"

f=../tests/guests/windows.img
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi

virt_tools_data_dir=${VIRT_TOOLS_DATA_DIR:-/usr/share/virt-tools}
if ! test -r $virt_tools_data_dir/rhsrvany.exe; then
    echo "$0: test skipped because rhsrvany.exe is not installed"
    exit 77
fi

d=test-v2v-networks-and-bridges.d
rm -rf $d
mkdir $d

# Use --no-copy because we only care about metadata for this test.
$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d --no-copy \
    --bridge "VM Network:bridge1" \
    -b bridge2 \
    --network default:network1 \
    --network john:network2 \
    -n paul:network3 \
    --network network4

# Test the libvirt XML metadata was created.
test -f $d/windows.xml

# Extract just the network interfaces from the XML.
# Delete the network model XML because that can change depending
# on whether virtio-win is installed or not.
sed -n '/interface/,/\/interface/p' $d/windows.xml |
  grep -v 'model type=' > $d/networks

# Test that the output has mapped the networks and bridges correctly.
diff -ur test-v2v-networks-and-bridges-expected.xml $d/networks

rm -r $d
