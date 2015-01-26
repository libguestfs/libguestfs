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

# Test -o vdsm options: --vmtype and --vdsm-*-uuid

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_O_VDSM_OPTIONS_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

abs_top_builddir="$(cd ..; pwd)"
libvirt_uri="test://$abs_top_builddir/tests/guests/guests.xml"

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

d=test-v2v-o-vdsm-options.d
rm -rf $d
mkdir $d

# Create a dummy Export Storage Domain.
mkdir $d/12345678-1234-1234-1234-123456789abc
mkdir $d/12345678-1234-1234-1234-123456789abc/images
mkdir $d/12345678-1234-1234-1234-123456789abc/images/IMAGE
mkdir $d/12345678-1234-1234-1234-123456789abc/master
mkdir $d/12345678-1234-1234-1234-123456789abc/master/vms
mkdir $d/12345678-1234-1234-1234-123456789abc/master/vms/VM

# The --vdsm-*-uuid options don't actually check that the
# parameter is a UUID, which is useful here.

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o vdsm -os $d/12345678-1234-1234-1234-123456789abc \
    --vmtype desktop \
    --vdsm-image-uuid IMAGE \
    --vdsm-vol-uuid VOL \
    --vdsm-vm-uuid VM \
    --vdsm-ovf-output $d/12345678-1234-1234-1234-123456789abc/master/vms/VM \

# Test the OVF metadata was created.
test -f $d/12345678-1234-1234-1234-123456789abc/master/vms/VM/VM.ovf

# Test the OVF metadata contains <VmType>0</VmType> (desktop).
grep '<VmType>0</VmType>' \
    $d/12345678-1234-1234-1234-123456789abc/master/vms/VM/VM.ovf

pushd $d/12345678-1234-1234-1234-123456789abc/images/IMAGE

# Test the disk .meta was created.
test -f VOL.meta

# Test the disk file was created.
test -f VOL

popd

rm -r $d
