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

# Test --mac parameter.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_builddir/test-v2v-mac.xml"
f=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-mac.d
rm -rf $d
mkdir $d

# Use --no-copy because we only care about metadata for this test.
$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d --no-copy \
    --mac 52:54:00:01:02:03:network:nancy \
    --mac 52:54:00:01:02:04:bridge:bob \
    --network default_network

# Test the libvirt XML metadata was created.
test -f $d/windows.xml

# Extract just the network interfaces from the XML.
# Delete the network model XML because that can change depending
# on whether virtio-win is installed or not.
sed -n '/interface/,/\/interface/p' $d/windows.xml |
  grep -v 'model type=' > $d/networks

# Test that the output has mapped the networks and bridges correctly.
diff -ur test-v2v-mac-expected.xml $d/networks

rm -r $d
