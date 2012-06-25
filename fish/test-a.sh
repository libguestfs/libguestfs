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

# Test guestfish -a option.

set -e

rm -f test.out

./guestfish -x -a /dev/null </dev/null >test.out 2>&1

! grep -sq 'add_drive.*format' test.out

./guestfish -x --format=raw -a /dev/null </dev/null >test.out 2>&1

grep -sq 'add_drive.*format:raw' test.out

./guestfish -x --ro --format=raw -a /dev/null </dev/null >test.out 2>&1

grep -sq 'add_drive.*readonly:true.*format:raw' test.out

./guestfish -x --format -a /dev/null </dev/null >test.out 2>&1

! grep -sq 'add_drive.*format' test.out

./guestfish -x -a /dev/null --format=raw </dev/null >test.out 2>&1

! grep -sq 'add_drive.*format' test.out

rm test.out
