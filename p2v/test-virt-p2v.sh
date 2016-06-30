#!/bin/bash -
# libguestfs virt-p2v test script
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

# Test virt-p2v in non-GUI mode.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_VIRT_P2V_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

guestsdir="$(cd ../test-data/phony-guests && pwd)"
f1="$guestsdir/windows.img"
if ! test -f $f1 || ! test -s $f1; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi
f2="$guestsdir/blank-part.img"
if ! test -f $f2 || ! test -s $f2; then
    echo "$0: test skipped because blank-part.img was not created"
    exit 77
fi

export VIRT_TOOLS_DATA_DIR="$srcdir/../test-data/fake-virt-tools"

d=test-virt-p2v.d
rm -rf $d
mkdir $d

# We don't want the program under test to run real 'ssh' or 'scp'.
# They won't work.  Therefore create dummy 'ssh' and 'scp' binaries.
pushd $d
ln -sf ../test-virt-p2v-ssh.sh ssh
ln -sf ../test-virt-p2v-scp.sh scp
popd
export PATH=$d:$PATH

# Note that the PATH already contains the local virt-p2v & virt-v2v
# binaries under test (because of the ./run script).

# The Linux kernel command line.
cmdline="p2v.server=localhost p2v.name=windows p2v.debug p2v.disks=$f1,$f2 p2v.o=local p2v.os=$(pwd)/$d p2v.network=em1:wired,other p2v.post="

virt-p2v --cmdline="$cmdline"

# Test the libvirt XML metadata and a disk was created.
test -f $d/windows.xml
test -f $d/windows-sda
test -f $d/windows-sdb

rm -r $d
