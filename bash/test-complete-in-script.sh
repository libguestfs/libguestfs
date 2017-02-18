#!/bin/bash -
# libguestfs bash completion test script
# Copyright (C) 2016 Red Hat Inc.
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

# Test that the correct 'complete' command is included in the script.
# Mainly prevents symlinking errors and some omissions.

$TEST_FUNCTIONS
skip_if_skipped

if [ -z "$commands" ]; then
    echo "$0: \$commands is not defined.  Use 'make check' to run this test."
    exit 1
fi

for cmd in $commands; do
    if [ ! -f $cmd ]; then
        echo "$0: script or symlink '$cmd' is missing"
        exit 1
    fi
    if ! grep "^complete.*$cmd\$" $cmd; then
        echo "$0: script or symlink '$cmd' does not have"
        echo "a 'complete' rule for '$cmd'"
        exit 1
    fi
done
