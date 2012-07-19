#!/bin/sh -
# Copyright (C) 2012 Red Hat Inc.
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

set -e
#set -x

if [ ! -d "$QEMUDIR" ]; then
    echo "$0: \$QEMUDIR not a directory, tests against upstream qemu skipped"
    exit 77
fi

QEMU="$QEMUDIR/x86_64-softmmu/qemu-system-x86_64"
if ! "$QEMU" --help >/dev/null 2>&1; then
    echo "$0: $QEMU not executable, tests against upstream qemu skipped"
    exit 77
fi

"$QEMU" --version

LIBGUESTFS_QEMU=$abs_srcdir/test-upstream-qemu-wrapper.sh
export LIBGUESTFS_QEMU
export QEMU

$MAKE -C ../.. quickcheck
$MAKE -C ../c-api check
