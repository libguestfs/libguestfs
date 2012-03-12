#!/bin/bash -
# libguestfs
# Copyright (C) 2010 Red Hat Inc.
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

# Test guestfish copy-in and copy-out commands.

# This test fails on some versions of mock which lack /dev/fd
# directory.  Skip this test in that case.

test -d /dev/fd || {
    echo "$0: Skipping this test because /dev/fd is missing."
    exit 0
}

set -e

rm -f test1.img
rm -rf original copy

mkdir original
cp $srcdir/../tests/data/known* original
cp -P $srcdir/../tests/data/abssymlink* original

output=$(
./guestfish -N fs -m /dev/sda1 <<EOF
mkdir /data
# This creates a directory /data/data/
copy-in original /data
is-file /data/original/known-1
is-file /data/original/known-3
is-file /data/original/known-5
is-symlink /data/original/abssymlink
is-file /data/known-1
is-file /known-1
EOF
)

if [ "$output" != \
"true
true
true
true
false
false" ]; then
    echo "$0: error: output of guestfish after copy-in command did not match expected output"
    echo "$output"
    exit 1
fi

mkdir copy

./guestfish --ro -a test1.img -m /dev/sda1 <<EOF
copy-out /data/original copy
EOF

if test ! -f copy/original/known-1 || \
   test ! -f copy/original/known-3 || \
   test ! -f copy/original/known-5 || \
   test ! -L copy/original/abssymlink || \
   test -f copy/known-1 || \
   test -f known-1
then
    echo "$0: error: copy-out command failed"
    exit 1
fi

rm -f test1.img
rm -rf original copy
