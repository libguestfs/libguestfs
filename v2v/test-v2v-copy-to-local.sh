#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2015 Red Hat Inc.
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

# Test virt-v2v-copy-to-local command.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_COPY_TO_LOCAL_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

abs_top_builddir="$(cd ..; pwd)"
libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"

f=../test-data/phony-guests/fedora.img
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because phony Fedora image was not created"
    exit 77
fi

d=test-v2v-copy-to-local.d
rm -rf $d
mkdir $d

pushd $d
$VG virt-v2v-copy-to-local --debug-gc -ic "$libvirt_uri" fedora
popd

# Test the libvirt XML metadata was created.
test -f $d/fedora.xml

# Test the disk was created.
test -f $d/fedora-disk1

rm -r $d
