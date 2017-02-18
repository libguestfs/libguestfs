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

set -e

$TEST_FUNCTIONS
skip_if_skipped

# This test fails on some versions of mock which lack /dev/fd
# directory.  Skip this test in that case.

test -d /dev/fd || {
    echo "$0: Skipping this test because /dev/fd is missing."
    exit 77
}

rm -f test-edit.img

# The command will be 'echo ... >>/tmp/tmpfile'
export EDITOR="echo second line of text >>"

output=$(
$VG guestfish -N test-edit.img=fs -m /dev/sda1 <<EOF
write /file.txt "this is a test\n"
chmod 0600 /file.txt
chown 10 11 /file.txt
edit /file.txt
cat /file.txt
stat /file.txt | grep mode:
stat /file.txt | grep uid:
stat /file.txt | grep gid:
echo ==========
write /file-2.txt "symlink test\n"
ln-s /file-2.txt /symlink-2.txt
edit /symlink-2.txt
is-symlink /symlink-2.txt
cat /symlink-2.txt
EOF
)

if [ "$output" != "this is a test
second line of text

mode: 33152
uid: 10
gid: 11
==========
true
symlink test
second line of text" ]; then
    echo "$0: error: output of guestfish after edit command did not match expected output"
    echo "$output"
    exit 1
fi

rm test-edit.img
