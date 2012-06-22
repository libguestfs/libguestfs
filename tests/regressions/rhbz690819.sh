#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# https://bugzilla.redhat.com/show_bug.cgi?id=690819
# mkfs fails creating a filesytem on a disk device when using a disk
# with 'ide' interface

# Allow this test to be skipped (eg. on ppc64)
#
# What happens on ppc64 is that we ask 'qemu-system-ppc64 -M pseries'
# to create an IDE disk.  It either creates it, or ignores it (not
# sure which), but the appliance fails to see the disk at all.  Thus
# logical device /dev/sda points to the appliance root filesystem, and
# the mkfs fails.  It's not clear how to solve this cleanly. XXX
[ -n "$SKIP_TEST_RHBZ690819_SH" ] && {
    echo "$0 skipped (environment variable set)"
    exit 0
}

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ690819_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 0
fi

rm -f test.img

../../fish/guestfish sparse test.img 100M

../../fish/guestfish <<EOF
add-drive-with-if test.img ide
run
mkfs ext3 /dev/sda
mount /dev/sda /
EOF

rm -f test.img
