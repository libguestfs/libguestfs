#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=895904
# Ensure we have a test of the 'checksums-out' command.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f rhbz895904.img rhbz895904.out

guestfish -N rhbz895904.img=fs -m /dev/sda1 <<EOF | sort -k 3 > rhbz895904.out
mkdir /test
touch /test/file1
mkdir /test/subdir
write /test/subdir/file2 abc
checksums-out crc /test -
EOF

if [ "$(cat rhbz895904.out)" != "4294967295 0 ./file1
1219131554 3 ./subdir/file2" ]; then
    echo "$0: unexpected output from checksums-out command:"
    cat rhbz895904.out
    exit 1
fi

rm rhbz895904.img rhbz895904.out
