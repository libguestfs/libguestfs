#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=909624
#
# Ensure that progress messages don't cause a stack overflow.  Note if
# this fails, it fails by causing guestfish to segfault (inside
# libguestfs).

set -e

$TEST_FUNCTIONS
slow_test
skip_if_skipped

guestfish <<EOF

add-ro /dev/null
run

# Generate a million progress messages.  Typically around 14000 is
# enough to trigger the stack overflow.
debug progress "1 1"

EOF
