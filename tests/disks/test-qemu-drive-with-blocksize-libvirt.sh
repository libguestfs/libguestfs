#!/bin/bash
# Copyright (C) 2013-2023 Red Hat Inc.
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

# Test that disks with <blockio .../> tag map to the correct qemu -device
# parameters and respect to logical_block_size value.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_libvirt_minimum_version 1 1 3

guestfish="guestfish -c test://$abs_builddir/disks/test-qemu-drive-libvirt.xml"

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_HV="${abs_srcdir}/disks/debug-qemu.sh"
export DEBUG_QEMU_FILE="${abs_builddir}/test-qemu-drive-with-blocksize-libvirt.out"

function check_output ()
{
    if [ ! -f "$DEBUG_QEMU_FILE" ]; then
        echo "$0: guestfish command failed, see previous error messages"
        exit 1
    fi
}

function fail ()
{
    echo "$0: Test $1 failed.  Command line output was:"
    cat "$DEBUG_QEMU_FILE"
    exit 1
}

# arg1 - is device number
function find_device()
{
    grep -shoe "-device \S*drive=hd${1}\S*" "$DEBUG_QEMU_FILE"
}

# arg1 - is device number
# arg2 - is expected blocksize
function check_blocksize_for_device()
{
    find_device ${1} | grep -sqEe "((physical|logical)_block_size=${2},?){2}" || fail hd${1}
}

rm -f "$DEBUG_QEMU_FILE"

LIBGUESTFS_DEBUG=1 $guestfish -d blocksize run ||:
check_output

# hd0 without explicitly specified physical/logical block size.
# We don't expect neither physical_ nor logical_block_size parameter.
find_device 0 | grep -sqhve '_block_size' || fail hd0

# hd1 with logical_block_size='512'.
check_blocksize_for_device 1 512

# hd2 with logical_block_size='4096'.
check_blocksize_for_device 2 4096

# hd3 with physical_block_size='4096' logical_block_size='512'.
check_blocksize_for_device 3 512

rm -f "$DEBUG_QEMU_FILE"
