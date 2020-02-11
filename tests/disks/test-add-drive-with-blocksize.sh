#!/bin/bash -
# libguestfs
# Copyright (C) 2020 Red Hat Inc.
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

# Test blocksize parameter of add-drive command

set -e

$TEST_FUNCTIONS
skip_if_skipped

# Test valid values
for expected_bs in 512 4096; do
    actual_bs=$(guestfish --ro add /dev/null blocksize:${expected_bs} : run : blockdev-getss /dev/sda)
    if [ "${actual_bs}" != "${expected_bs}" ]; then
        echo "$0: error: actual blocksize doesn't match expected: ${actual_bs} != ${expected_bs}"
        exit 1
    fi
done

# Test without blocksize parameter
expected_bs=512
actual_bs=$(guestfish --ro add /dev/null : run : blockdev-getss /dev/sda)

if [ "${actual_bs}" != "${expected_bs}" ]; then
    echo "$0: error: actual blocksize doesn't match expected: ${actual_bs} != ${expected_bs}"
    exit 1
fi

# Negative tests
for blocksize in 256 1000 2048 8192 65536; do
    if guestfish --ro add /dev/null blocksize:${blocksize}; then
        echo "$0: error: blocksize:${blocksize} should not be supported"
        exit 1
    fi
done
