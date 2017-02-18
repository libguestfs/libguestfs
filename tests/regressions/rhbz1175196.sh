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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=1175196
# Parse 'LIBGUESTFS_TRACE=0' in the environment.

set -e

$TEST_FUNCTIONS
skip_if_skipped

output="$(guestfish <<EOF

setenv LIBGUESTFS_TRACE 1
parse-environment
get-trace

setenv LIBGUESTFS_TRACE 0
parse-environment
get-trace

setenv LIBGUESTFS_TRACE true
parse-environment
get-trace

setenv LIBGUESTFS_TRACE no
parse-environment
get-trace

setenv LIBGUESTFS_TRACE t
parse-environment
get-trace

setenv LIBGUESTFS_TRACE f
parse-environment
get-trace

EOF
)"

if [ "$output" != "true
false
true
false
true
false" ]; then
    echo "$0: unexpected output from test:"
    echo "$output"
    exit 1
fi
