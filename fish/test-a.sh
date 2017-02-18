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

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-a.out
rm -f test-a.img

$VG guestfish sparse test-a.img 100M

$VG guestfish -x -a test-a.img </dev/null >test-a.out 2>&1

! grep -sq 'add_drive.*format' test-a.out

rm test-a.img
$VG guestfish disk-create test-a.img qcow2 100M

$VG guestfish -x --format=qcow2 -a test-a.img </dev/null >test-a.out 2>&1

grep -sq 'add_drive.*format:qcow2' test-a.out

$VG guestfish -x --ro --format=qcow2 -a test-a.img </dev/null >test-a.out 2>&1

grep -sq 'add_drive.*readonly:true.*format:qcow2' test-a.out

$VG guestfish -x --format -a test-a.img </dev/null >test-a.out 2>&1

! grep -sq 'add_drive.*format' test-a.out

$VG guestfish -x -a test-a.img --format=raw -a /dev/null </dev/null >test-a.out 2>&1

! grep -sq 'add_drive.*test-a.img.*format' test-a.out

rm test-a.out
rm test-a.img
