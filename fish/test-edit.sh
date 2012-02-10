#!/bin/bash -
# libguestfs
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

# Test guestfish edit command.

# This test fails on some versions of mock which lack /dev/fd
# directory.  Skip this test in that case.

test -d /dev/fd || {
    echo "$0: Skipping this test because /dev/fd is missing."
    exit 0
}

set -e

rm -f test1.img

# The command will be 'echo ... >>/tmp/tmpfile'
export EDITOR="echo second line of text >>"

output=$(
../fish/guestfish -N fs -m /dev/sda1 <<EOF
write /file.txt "this is a test\n"
chmod 0600 /file.txt
chown 10 11 /file.txt
edit /file.txt
cat /file.txt
stat /file.txt | grep mode:
stat /file.txt | grep uid:
stat /file.txt | grep gid:
EOF
)

if [ "$output" != "this is a test
second line of text

mode: 33152
uid: 10
gid: 11" ]; then
    echo "$0: error: output of guestfish after edit command did not match expected output"
    echo "$output"
    exit 1
fi

rm -f test1.img
