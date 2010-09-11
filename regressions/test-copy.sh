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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Test guestfish copy-in and copy-out commands.

set -e

rm -f test1.img
rm -rf copy

output=$(
../fish/guestfish -N fs -m /dev/sda1 <<EOF
mkdir /data
# This creates a directory /data/images/
copy-in ../images /data
is-file /data/images/known-1
is-file /data/images/known-3
is-file /data/images/known-5
is-symlink /data/images/abssymlink
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

../fish/guestfish --ro -a test1.img -m /dev/sda1 <<EOF
copy-out /data/images copy
EOF

if test ! -f copy/images/known-1 || \
   test ! -f copy/images/known-3 || \
   test ! -f copy/images/known-5 || \
   test ! -L copy/images/abssymlink || \
   test -f copy/known-1 || \
   test -f known-1
then
    echo "$0: error: copy-out command failed"
    exit 1
fi

rm -f test1.img
rm -rf copy