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

# Test -i ova option with two disks.

unset CDPATH
export LANG=C
set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"
export VIRTIO_WIN="$top_srcdir/test-data/fake-virtio-win"

d=test-v2v-i-ova-two-disks.d
rm -rf $d
mkdir $d

pushd $d

# Create a phony OVA.  This is only a test of source parsing, not
# conversion, so the contents of the disks doesn't matter.
guestfish disk-create disk1.vmdk raw 10K
sha=`do_sha1 disk1.vmdk`
echo -e "SHA1(disk1.vmdk)= $sha\r" > disk1.mf
guestfish disk-create disk2.vmdk raw 100K
sha=`do_sha1 disk2.vmdk`
echo -e "SHA1(disk2.vmdk)= $sha\r" > disk2.mf
cp ../test-v2v-i-ova-two-disks.ovf .

tar -cf test.ova test-v2v-i-ova-two-disks.ovf disk1.vmdk disk1.mf disk2.vmdk disk2.mf
popd

# Run virt-v2v but only as far as the --print-source stage, and
# normalize the output.
$VG virt-v2v --debug-gc --quiet \
    -i ova $d/test.ova \
    --print-source  > $d/source

# Check the parsed source is what we expect.
if grep -sq json: $d/source ; then
    # Normalize the output.
    # Remove directory prefix.
    # Exact offset will vary because of tar.
    sed -i -e "s,\"[^\"]*/$d/,\"," \
           -e "s|\"offset\": [0-9]*,|\"offset\": x,|" $d/source
    diff -u test-v2v-i-ova-two-disks.expected2 $d/source
else
    # normalize the output
    sed -i -e 's,[^ \t]*\(disk.*.vmdk\),\1,' $d/source
    diff -u test-v2v-i-ova-two-disks.expected $d/source
fi

rm -rf $d
