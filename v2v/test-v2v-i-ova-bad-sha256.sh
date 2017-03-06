#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2014-2017 Red Hat Inc.
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

# Test -i ova option with a good manifest containing a bad SHA256 checksum.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

if [ ! -f windows.vmdk -o ! -s windows.vmdk ]; then
    echo "$0: test skipped because windows.vmdk was not created"
    exit 77
fi

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-i-ova-bad-sha256.d
rm -rf $d
mkdir $d

pushd $d

# Create the test OVA.
cp ../test-v2v-i-ova-checksums.ovf test.ovf
cp ../windows.vmdk disk.vmdk
echo "SHA256(test.ovf)=" `do_sha256 test.ovf` > test.mf
sha256=`do_sha256 disk.vmdk | tr '0-5a-f6789' 'a-f0-58967'`
echo "SHA256(disk.vmdk)=" $sha256 >> test.mf
tar cf test.ova test.ovf disk.vmdk test.mf

# Run virt-v2v but only as far as the --print-source stage.
# It is expected to fail with an error.
if $VG virt-v2v --debug-gc --quiet \
       -i ova test.ova \
       --print-source >test.out 2>&1; then
    cat test.out
    echo "$0: expected virt-v2v to fail, but it succeeded"
    exit 1
fi
cat test.out
if ! grep "error: checksum of disk disk.vmdk does not match manifest" test.out
then
    echo "$0: did not see the expected error in the output of virt-v2v"
    exit 1
fi

popd
rm -rf $d
