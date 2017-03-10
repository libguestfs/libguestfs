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

# Regression test for the case where a OVA file is only readable as
# root.  Because libvirt runs qemu as qemu.qemu in this case, qemu
# cannot open the OVA file.  See:
# https://bugzilla.redhat.com/show_bug.cgi?id=1375157#c6
# https://bugzilla.redhat.com/show_bug.cgi?id=1430680

set -e

$TEST_FUNCTIONS
root_test
skip_if_skipped
skip_unless_backend libvirt
skip_unless_phony_guest windows.img

if [ ! -f windows.vmdk -o ! -s windows.vmdk ]; then
    echo "$0: test skipped because windows.vmdk was not created"
    exit 77
fi

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-i-ova-as-root.d
rm -rf $d
mkdir $d

pushd $d

# Create the test OVA.
cp ../test-v2v-i-ova-as-root.ovf test.ovf
cp ../windows.vmdk disk.vmdk

echo "SHA1(test.ovf)=" `do_sha1 test.ovf` > test.mf
echo "SHA1(disk.vmdk)=" `do_sha1 disk.vmdk` >> test.mf

tar cf test.ova test.ovf disk.vmdk test.mf

# So it's unreadable by non-root.
chown root.root test.ova
chmod 0600 test.ova

# Run virt-v2v.
$VG virt-v2v --debug-gc --quiet \
    -i ova test.ova \
    -o null

popd
rm -rf $d
