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

# Test -i ova option with OVA file containing snapshots.
# https://bugzilla.redhat.com/show_bug.cgi?id=1570407

unset CDPATH
export LANG=C
set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-i-ova-snapshots.d
rm -rf $d
mkdir $d

pushd $d

# Create a phony OVA.  This is only a test of source parsing, not
# conversion, so the contents of the disks doesn't matter.
# In these weird OVAs, disk1.vmdk does not exist, but both the
# href and manifest reference it.  virt-v2v should use the
# highest numbered snapshot instead.
guestfish disk-create disk1.vmdk.000000000 raw 10k
guestfish disk-create disk1.vmdk.000000001 raw 11k
guestfish disk-create disk1.vmdk.000000002 raw 12k
sha=`do_sha1 disk1.vmdk.000000002`
echo -e "SHA1(disk1.vmdk)= $sha\r" > disk1.mf
sha=`do_sha1 disk1.vmdk.000000000`
echo -e "SHA1(disk1.vmdk.000000000)= $sha\r" > disk1.mf
sha=`do_sha1 disk1.vmdk.000000001`
echo -e "SHA1(disk1.vmdk.000000001)= $sha\r" > disk1.mf
sha=`do_sha1 disk1.vmdk.000000002`
echo -e "SHA1(disk1.vmdk.000000002)= $sha\r" > disk1.mf
cp ../test-v2v-i-ova-snapshots.ovf .
tar -cf test-snapshots.ova test-v2v-i-ova-snapshots.ovf disk1.vmdk.00000000? disk1.mf

popd

# Run virt-v2v but only as far as the --print-source stage
$VG virt-v2v --debug-gc --quiet \
    -i ova $d/test-snapshots.ova \
    --print-source > $d/source

# Check the parsed source is what we expect.
if grep -sq json: $d/source ; then
    # Normalize the output.
    # Remove directory prefix.
    # Exact offset will vary because of tar.
    sed -i -e "s,\"[^\"]*/$d/,\"," \
           -e "s|\"offset\": [0-9]*,|\"offset\": x,|" $d/source
    diff -u test-v2v-i-ova-snapshots.expected2 $d/source
else
    # normalize the output
    sed -i -e 's,[^ \t]*\(disk.*.vmdk\),\1,' $d/source
    diff -u test-v2v-i-ova-snapshots.expected $d/source
fi

rm -rf $d
