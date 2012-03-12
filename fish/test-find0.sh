#!/bin/bash -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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

# Test find0 call.

set -e

rm -f test.out

./guestfish <<'EOF'
add-ro ../tests/data/test.iso
run
mount-ro /dev/sda /
find0 / test.out
EOF

n=$(tr '\0' '\n' < test.out | grep '^known-[1-5]' | wc -l)
[ "$n" = 5 ] || {
  echo find0: Invalid list of files
  tr '\0' '\n' < test.out
  exit 1
}

rm -f test.out
