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
export LANG=C

output=`
../../fish/guestfish -N fs -m /dev/sda1 <<EOF | sort -k 3
mkdir /test
touch /test/file1
mkdir /test/subdir
write /test/subdir/file2 abc
checksums-out crc /test -
EOF
`

if [ "$output" != "4294967295 0 ./file1
1219131554 3 ./subdir/file2" ]; then
    echo "$0: unexpected output from checksums-out command:"
    echo "$output"
    exit 1
fi

rm test1.img
