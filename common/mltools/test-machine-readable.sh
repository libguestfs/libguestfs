#!/bin/bash -
# libguestfs
# Copyright (C) 2018 Red Hat Inc.
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

# Test the --machine-readable functionality of the module Tools_utils.
# See also: machine_readable_tests.ml

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

t=./machine_readable_tests

tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir"

# Clean up if the script is killed or exits early.
cleanup ()
{
    status=$?
    rm -rf "$tmpdir"
    exit $status
}
trap cleanup INT QUIT TERM EXIT ERR

# Program works.
$t

# No machine-readable output.
$t | grep 'machine-readable' && test $? = 1
test $($t | wc -l) -eq 1
test $($t |& wc -l) -eq 2

# Default output: stdout.
$t --machine-readable | grep 'machine-readable'
test $($t --machine-readable | wc -l) -eq 2
test $($t --machine-readable |& wc -l) -eq 3

# Output "file:".
fn="$tmpdir/file"
$t --machine-readable=file:"$fn"
test $(cat "$fn" | wc -l) -eq 1

# Output "stream:stdout".
$t --machine-readable=stream:stdout | grep 'machine-readable'
test $($t --machine-readable=stream:stdout | wc -l) -eq 2
test $($t --machine-readable=stream:stdout |& wc -l) -eq 3

# Output "stream:stderr".
$t --machine-readable=stream:stderr 2>&1 >/dev/null | grep 'machine-readable'
test $($t --machine-readable=stream:stderr 2>&1 >/dev/null | wc -l) -eq 2

# Output "fd:".
fn="$tmpdir/fdfile"
exec 4>"$fn"
$t --machine-readable=fd:4
exec 4>&-
test $(cat "$fn" | wc -l) -eq 1
