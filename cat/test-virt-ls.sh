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

export LANG=C
set -e

# Read out the test directory using virt-ls.
if [ "$(./virt-ls ../tests/guests/fedora.img /bin)" != "ls
test1
test2
test3
test4
test5
test6
test7" ]; then
    echo "$0: error: unexpected output from virt-ls"
    exit 1
fi

# Try the -lR option.
output="$(./virt-ls -lR ../tests/guests/fedora.img /boot | awk '{print $1 $2 $4}')"
expected="d0755/boot
d0755/boot/grub
-0644/boot/grub/grub.conf
d0700/boot/lost+found"
if [ "$output" != "$expected" ]; then
    echo "$0: error: unexpected output from virt-ls -lR"
    echo "output: ------------------------------------------"
    echo "$output"
    echo "expected: ----------------------------------------"
    echo "$expected"
    echo "--------------------------------------------------"
    exit 1
fi
