#!/bin/bash -
# libguestfs
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

# Test guestfish alloc and sparse commands.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-alloc.img

$VG guestfish alloc test-alloc.img 200000
if [ "$(stat -c '%s' test-alloc.img)" -ne 200000 ]; then
    echo "$0: alloc command failed to create file of the correct size"
    exit 1
fi

if [ "$(stat -c '%b' test-alloc.img)" -eq 0 ]; then
    echo "$0: alloc command failed to create a fully allocated file"
    exit 1
fi

$VG guestfish sparse test-alloc.img 100000
if [ "$(stat -c '%s' test-alloc.img)" -ne 100000 ]; then
    echo "$0: sparse command failed to create file of the correct size"
    exit 1
fi

if [ "$(stat -c '%b' test-alloc.img)" -ne 0 ]; then
    echo "$0: sparse command failed to create a sparse file"
    exit 1
fi

rm test-alloc.img
