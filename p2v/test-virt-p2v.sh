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

f="$(cd ../tests/guests && pwd)/windows.img"
if ! test -f $f || ! test -s $f; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi

virt_tools_data_dir=${VIRT_TOOLS_DATA_DIR:-/usr/share/virt-tools}
if ! test -r $virt_tools_data_dir/rhsrvany.exe; then
    echo "$0: test skipped because rhsrvany.exe is not installed"
    exit 77
fi

d=test-virt-p2v.d
rm -rf $d
mkdir $d

# We don't want to program under test to actually ssh.  It's unlikely
# to work.  Therefore create a dummy 'ssh' binary.
pushd $d
ln -sf ../test-virt-p2v-ssh.sh ssh
popd
export PATH=$d:$PATH

# Note that the PATH already contains the local virt-v2v binary
# under test (because of the ./run script).

# The Linux kernel command line.
cmdline="p2v.server=localhost p2v.name=windows p2v.debug p2v.disks=$f p2v.o=local p2v.os=$d p2v.network=em1:wired,other p2v.post="

virt-p2v --cmdline="$cmdline"

# Test the libvirt XML metadata and a disk was created.
test -f $d/windows.xml
test -f $d/windows-sda

rm -r $d
