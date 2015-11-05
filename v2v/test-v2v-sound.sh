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

# Test <sound> is transferred to destination domain.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_SOUND_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

abs_builddir="$(pwd)"
libvirt_uri="test://$abs_builddir/test-v2v-sound.xml"

f=../test-data/phony-guests/windows.img
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi

export VIRT_TOOLS_DATA_DIR="$srcdir/../test-data/fake-virt-tools"

d=test-v2v-sound.d
rm -rf $d
mkdir $d

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d --no-copy

# Test the libvirt XML metadata was created.
test -f $d/windows.xml

# Check the <sound> element exists in the output.
grep 'sound model=.ich9' $d/windows.xml

rm -r $d
