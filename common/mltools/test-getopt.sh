#!/bin/bash -
# libguestfs
# Copyright (C) 2016-2018 Red Hat Inc.
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

# Test the Getopt module.
# See also: getopt_tests.ml

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

t=./getopt_tests

expect_fail ()
{
    if "$@"; then
        echo "$@" ": this command was expected to exit with an error"
        exit 1
    fi
}

# Program works.
$t

# Flags added automatically by Tools_utils.
$t | grep '^trace = false'
$t | grep '^verbose = false'

$t -x | grep '^trace = true'
$t --verbose | grep '^verbose = true'

# --help
$t --help | grep '^getopt_tests: test the Getopt parser'
$t --help | grep '^Options:'
$t --help | grep -- '-i, --int <int>'
$t --help | grep -- '-ii, --set-int <int>'
$t --help | grep -- '-v, --verbose'
$t --help | grep -- '-x'

# --version
$t --version | grep '^getopt_tests 1\.'

# --short-options
$t --short-options | grep '^-a'
$t --short-options | grep '^-c'
$t --short-options | grep '^-i'
$t --short-options | grep '^-q'
$t --short-options | grep '^-ii'
$t --short-options | grep '^-is'
$t --short-options | grep '^-t'
$t --short-options | grep '^-V'
$t --short-options | grep '^-v'
$t --short-options | grep '^-x'

# --long-options
$t --long-options | grep '^--help'
$t --long-options | grep '^--add'
$t --long-options | grep '^--clear'
$t --long-options | grep '^--color'
$t --long-options | grep '^--colors'
$t --long-options | grep '^--colour'
$t --long-options | grep '^--colours'
$t --long-options | grep '^--debug-gc'
$t --long-options | grep '^--int'
$t --long-options | grep '^--quiet'
$t --long-options | grep '^--set'
$t --long-options | grep '^--set-int'
$t --long-options | grep '^--set-string'
$t --long-options | grep '^--ii'
$t --long-options | grep '^--is'
$t --long-options | grep '^--version'
$t --long-options | grep '^--verbose'

# -a/--add parameter.
$t | grep '^adds = \[\]'
$t -a A | grep '^adds = \[A\]'
$t -a A -a B | grep '^adds = \[A, B\]'
$t --add A | grep '^adds = \[A\]'
$t --add A -a B | grep '^adds = \[A, B\]'
expect_fail $t -a
expect_fail $t --add

# -c/--clear parameter.
$t | grep '^clear_flag = true'
$t -c | grep '^clear_flag = false'
$t --clear | grep '^clear_flag = false'

# -i/--int parameter.
$t | grep '^ints = \[\]'
$t -i 1 | grep '^ints = \[1\]'
$t -i 1 -i 2 | grep '^ints = \[1, 2\]'
$t -i 1 --int 2 --int 3 | grep '^ints = \[1, 2, 3\]'
expect_fail $t --int

# Non-integer parameters.
expect_fail $t --int --int
expect_fail $t --int ""
expect_fail $t --int ABC
expect_fail $t --int 0.3
expect_fail $t --int 0E
expect_fail $t --int 0ABC

# Negative and large integer parameters.
# All int parameters must be within signed 31 bit (even on 64 bit arch),
# and anything else should be rejected.
$t -i -1 | grep '^ints = \[-1\]'
$t -i -1073741824 | grep '^ints = \[-1073741824\]'
$t -i  1073741823 | grep '^ints = \[1073741823\]'
expect_fail $t -i -1073741825
expect_fail $t -i  1073741824
expect_fail $t -i -2147483648
expect_fail $t -i  2147483647
expect_fail $t -i -4611686018427387904
expect_fail $t -i  4611686018427387903
expect_fail $t -i -9223372036854775808
expect_fail $t -i  9223372036854775807

# -t/--set parameter.
$t | grep '^set_flag = false'
$t -t | grep '^set_flag = true'
$t --set | grep '^set_flag = true'

# --ii/--set-int parameter.
$t | grep '^set_int = 42'
$t --ii 1 | grep '^set_int = 1'
$t --set-int 2 | grep '^set_int = 2'
expect_fail $t --ii
expect_fail $t --set-int
expect_fail $t --set-int -i
expect_fail $t --set-int ""
expect_fail $t --set-int ABC
expect_fail $t --set-int 0.3
expect_fail $t --set-int 1e1
expect_fail $t --set-int 0E
expect_fail $t --set-int 0ABC

# --is/--set-string parameter.
$t | grep '^set_string = not set'
$t --is A | grep '^set_string = A'
$t --set-string B | grep '^set_string = B'
expect_fail $t --is
expect_fail $t --set-string

# Anonymous parameters.
$t | grep '^anons = \[\]'
$t 1 | grep '^anons = \[1\]'
$t 1 2 3 | grep '^anons = \[1, 2, 3\]'

# Grouping single letter options.
$t -cti1 | grep '^clear_flag = false'
$t -cti1 | grep '^set_flag = true'
$t -cti1 | grep '^ints = \[1\]'
$t -i1 -i2 | grep '^ints = \[1, 2\]'

# Short versions of long options (used by virt-v2v).
$t -ii 1 | grep '^set_int = 1'
$t -is A | grep '^set_string = A'
