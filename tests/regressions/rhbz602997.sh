#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# https://bugzilla.redhat.com/show_bug.cgi?id=602997
# Fix part-get-bootable to work with missing/unordered partitions.

set -e
export LANG=C

guestfish=../../fish/guestfish

rm -f test.img test.output

$guestfish > test.output <<EOF
sparse test.img 100M
run
part-init /dev/sda mbr
# Create an unordered layout.
# This places part 2 in front of part 1.
part-add /dev/sda p 1001 2000
part-add /dev/sda p 1 1000
#part-list /dev/sda
part-set-bootable /dev/sda 1 true
part-get-bootable /dev/sda 1
part-get-bootable /dev/sda 2
EOF

if [ "$(cat test.output)" != "true
false" ]; then
    echo "rhbz602997.sh: Unexpected output from test:"
    cat test.output
    echo "[end of output]"
    exit 1
fi

$guestfish > test.output <<EOF
sparse test.img 100M
run
part-init /dev/sda mbr
part-add /dev/sda p 1 1000
part-add /dev/sda p 1001 2000
part-add /dev/sda p 2001 3000
part-del /dev/sda 2
#part-list /dev/sda
part-get-bootable /dev/sda 3
ping-daemon
EOF

if [ "$(cat test.output)" != "false" ]; then
    echo "rhbz602997.sh: Unexpected output from test:"
    cat test.output
    echo "[end of output]"
    exit 1
fi

rm -f test.img test.output
