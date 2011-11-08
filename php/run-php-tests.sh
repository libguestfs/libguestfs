#!/bin/sh -
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

set -e
cd extension

TESTS=$(echo guestfs_php_*.phpt)
echo TESTS: $TESTS

# The PHP test script cleans the environment, so LIBGUESTFS_DEBUG=1
# won't get passed down to the script.  Furthermore, setting
# LIBGUESTFS_DEBUG=1 isn't very useful anyway because the PHP test
# script mixes stdout and stderr together and compares this to the
# expected output, so you'd just get failures for every test.  So
# there is no good way to debug libguestfs failures in PHP tests, but
# if an individual test fails locally then you can edit the
# guestfs_php_*.phpt and uncomment the putenv statement, then look at
# the output.
unset LIBGUESTFS_DEBUG

# By the way, we're actually testing the installed version of
# libguestfs.  But don't worry, because PHP ignores the result of the
# tests anyway! ** Gah, PHP is written by morons ... **
make test TESTS="$TESTS"
