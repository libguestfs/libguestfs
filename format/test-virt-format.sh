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

# Test virt-format command.

set -e

rm -f test1.img

../fish/guestfish -N bootrootlv exit

./virt-format --filesystem=ext3 -a test1.img

if [ "$(../cat/virt-filesystems -a test1.img)" != "/dev/sda1" ]; then
    echo "$0: unexpected output after using virt-format"
    exit 1
fi

rm -f test1.img
