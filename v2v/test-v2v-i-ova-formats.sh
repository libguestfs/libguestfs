#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2014-2015 Red Hat Inc.
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

# Test -i ova option with ova file compressed in different ways

unset CDPATH
export LANG=C
set -e

formats="tar zip"

if [ -n "$SKIP_TEST_V2V_I_OVA_FORMATS_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if ! zip --version >/dev/null 2>&1; then
    echo "$0: test skipped because 'zip' utility is not available"
    exit 77
fi

if ! unzip --help >/dev/null 2>&1; then
    echo "$0: test skipped because 'unzip' utility is not available"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

virt_tools_data_dir=${VIRT_TOOLS_DATA_DIR:-/usr/share/virt-tools}
if ! test -r $virt_tools_data_dir/rhsrvany.exe; then
    echo "$0: test skipped because rhsrvany.exe is not installed"
    exit 77
fi

d=test-v2v-i-ova-formats.d
rm -rf $d
mkdir $d

pushd $d

# Create a phony OVA.  This is only a test of source parsing, not
# conversion, so the contents of the disks doesn't matter.
truncate -s 10k disk1.vmdk
sha=`sha1sum disk1.vmdk | awk '{print $1}'`
echo -e "SHA1(disk1.vmdk)=$sha\r" > disk1.mf

for format in $formats; do
    case "$format" in
        tar)
            tar -cf test-$format.ova ../test-v2v-i-ova-formats.ovf disk1.vmdk disk1.mf
            ;;
        zip)
            zip -r test ../test-v2v-i-ova-formats.ovf disk1.vmdk disk1.mf
            mv test.zip test-$format.ova
            ;;
        *)
            echo "Unhandled format '$format'"
            exit 1
    esac
done

popd

for format in $formats; do
    # Run virt-v2v but only as far as the --print-source stage, and
    # normalize the output.
    $VG virt-v2v --debug-gc --quiet \
        -i ova $d/test-$format.ova \
        --print-source |
    sed 's,[^ \t]*\(disk.*.vmdk\),\1,' > $d/source

    # Check the parsed source is what we expect.
    diff -u test-v2v-i-ova-formats.expected $d/source
done

rm -rf $d
