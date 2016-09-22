#!/bin/bash
# Copyright (C) 2013-2016 Red Hat Inc.
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

# Test that disks map to the correct qemu -drive parameter.

export LANG=C

set -e

if [ -z "$abs_srcdir" ]; then
    echo "$0: abs_srcdir environment variable must be set"
    exit 1
fi

if [ -z "$abs_builddir" ]; then
    echo "$0: abs_builddir environment variable must be set"
    exit 1
fi

if [ ! -x ../../src/libvirt-is-version ]; then
    echo "$0: test skipped because libvirt-is-version is not built yet"
    exit 77
fi

if ! ../../src/libvirt-is-version 1 1 3; then
    echo "$0: test skipped because libvirt is too old (< 1.1.3)"
    exit 77
fi

guestfish="guestfish -c test://$abs_builddir/test-qemu-drive-libvirt.xml"

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_HV="${abs_srcdir}/debug-qemu.sh"
export DEBUG_QEMU_FILE="${abs_builddir}/test-qemu-drive-libvirt.out"

# Setup the fake pool.
pool_dir=tmp
rm -rf "$pool_dir"
mkdir "$pool_dir"
touch "$pool_dir/in-pool"

function check_output ()
{
    if [ ! -f "$DEBUG_QEMU_FILE" ]; then
        echo "$0: guestfish command failed, see previous error messages"
        exit 1
    fi
}

function fail ()
{
    echo "$0: Test failed.  Command line output was:"
    cat "$DEBUG_QEMU_FILE"
    exit 1
}

rm -f "$DEBUG_QEMU_FILE"

# Ceph (RBD).

$guestfish -d ceph1 run ||:
check_output
grep -sq -- '-drive file=rbd:abc-def/ghi-jkl:mon_host=1.2.3.4\\:1234\\;1.2.3.5\\:1235\\;1.2.3.6\\:1236:auth_supported=none,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

$guestfish -d ceph2 run ||:
check_output
grep -sq -- '-drive file=rbd:abc-def/ghi-jkl:auth_supported=none,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# Gluster.

$guestfish -d gluster run ||:
check_output
grep -sq -- '-drive file=gluster://1.2.3.4:1234/volname/image,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# iSCSI.

$guestfish -d iscsi run ||:
check_output
grep -sq -- '-drive file=iscsi://1.2.3.4:1234/iqn.2003-01.org.linux-iscsi.fedora,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# NBD.

$guestfish -d nbd run ||:
check_output
grep -sq -- '-drive file=nbd:1.2.3.4:1234,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# Sheepdog.

$guestfish -d sheepdog run ||:
check_output
grep -sq -- '-drive file=sheepdog:volume,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# Local, stored in a pool.

$guestfish -d pool1 run ||:
check_output
grep -sq -- "-drive file=$abs_builddir/tmp/in-pool" "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# To do:

# HTTP - curl not yet supported by libvirt

# SSH.

# Clean up.
rm -r "$pool_dir"
