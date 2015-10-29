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

# Test -o libvirt.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_O_LIBVIRT_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

# You shouldn't be running the tests as root anyway, but in this case
# it's especially bad because we don't want to start creating guests
# or storage pools in the system namespace.
if [ "$(id -u)" -eq 0 ]; then
    echo "$0: test skipped because you're running tests as root.  Don't do that!"
    exit 77
fi

# Since libvirt ~ 1.2.19, it started to check that the guest
# architecture was valid at guest creation time, rather than when you
# first run the guest.  Since the guest XML contains arch='x86_64',
# this test will fail on !x86_64.
if [ "$(uname -m)" != "x86_64" ]; then
    echo "$0: test skipped because !x86_64"
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

# Generate a random guest name.
guestname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

d=test-v2v-o-libvirt.d
rm -rf $d
mkdir $d

# Set up the output directory as a libvirt storage pool.
virsh pool-destroy test-v2v-libvirt ||:
virsh pool-create-as test-v2v-libvirt dir - - - - $(pwd)/$d

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o libvirt -os test-v2v-libvirt -on $guestname

# Test the disk was created.
test -f $d/$guestname-sda

# Test the guest exists.
virsh dumpxml $guestname

# Clean up.
virsh pool-destroy test-v2v-libvirt ||:
virsh undefine $guestname ||:
rm -r $d
