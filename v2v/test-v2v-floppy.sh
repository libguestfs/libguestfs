#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2015-2016 Red Hat Inc.
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

# Test converting a guest with a floppy disk.
# https://bugzilla.redhat.com/show_bug.cgi?id=1309706

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_FLOPPY_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

abs_builddir="$(pwd)"
libvirt_uri="test://$abs_builddir/test-v2v-floppy.xml"

f=../test-data/phony-guests/windows.img
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi

f=../test-data/phony-guests/blank-disk.img
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because blank-disk.img was not created"
    exit 77
fi

export VIRT_TOOLS_DATA_DIR="$srcdir/../test-data/fake-virt-tools"
export VIRTIO_WIN="$srcdir/../test-data/fake-virtio-win"

d=test-v2v-floppy.d
rm -rf $d
mkdir $d

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d --no-copy

# Test the libvirt XML metadata was created.
test -f $d/windows.xml

# Grab just the <disk>..</disk> output and compare it to what we
# expect.  https://stackoverflow.com/questions/16587218
awk '/<disk /{p=1;print;next} p&&/<\/disk>/{p=0;print;next} ;p' \
    $d/windows.xml |
    grep -v '<source file' > $d/disks

if ! diff -u test-v2v-floppy.expected $d/disks; then
    echo "$0: unexpected disk assignments"
    cat $d/disks
    exit 1
fi

rm -r $d
