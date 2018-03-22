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

# Test -o vdsm options -oo vdsm-*-uuid

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
f=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"
export VIRTIO_WIN="$top_srcdir/test-data/fake-virtio-win"

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

# The -oo vdsm-*-uuid options don't actually check that the
# parameter is a UUID, which is useful here.

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o vdsm -os $d/12345678-1234-1234-1234-123456789abc \
    -of qcow2 \
    -oo vdsm-image-uuid=IMAGE \
    -oo vdsm-vol-uuid=VOL \
    -oo vdsm-vm-uuid=VM \
    -oo vdsm-ovf-output=$d/12345678-1234-1234-1234-123456789abc/master/vms/VM \
    -oo vdsm-compat=1.1 \
    -oo vdsm-ovf-flavour=ovirt

# Test the OVF metadata was created.
test -f $d/12345678-1234-1234-1234-123456789abc/master/vms/VM/VM.ovf

pushd $d/12345678-1234-1234-1234-123456789abc/images/IMAGE

# Test the disk .meta was created.
test -f VOL.meta

# Test the disk file was created.
test -f VOL

# Test that a qcow2 file with compat=1.1 was generated.
test "$(guestfish disk-format VOL)" = "qcow2"
qemu-img info VOL | grep 'compat: 1.1'

popd

rm -r $d
