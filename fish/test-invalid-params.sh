#!/bin/bash -
# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Test passing invalid parameters for memory size, smp, etc when setting up
# the appliance.

set -e

$TEST_FUNCTIONS
skip_if_skipped

# Memory size
output=$(
$VG guestfish <<EOF
set-memsize 400
-set-memsize 0
-set-memsize 100
-set-memsize -500
-set-memsize 0x10
-set-memsize 010
-set-memsize -1073741824
get-memsize
EOF
)
if [ "$output" != "400" ]; then
    echo "$0: error: output of guestfish after memsize commands did not match expected output"
    echo "$output"
    exit 1
fi

# smp
output=$(
$VG guestfish <<EOF
set-smp 2
-set-smp 0
-set-smp 300
-set-smp -2
get-smp
EOF
)
if [ "$output" != "2" ]; then
    echo "$0: error: output of guestfish after smp commands did not match expected output"
    echo "$output"
    exit 1
fi

# Backend
output=$(
$VG guestfish <<EOF
set-backend direct
-set-backend backend-which-does-not-exist
get-backend
EOF
)
if [ "$output" != "direct" ]; then
    echo "$0: error: output of guestfish after backend commands did not match expected output"
    echo "$output"
    exit 1
fi
