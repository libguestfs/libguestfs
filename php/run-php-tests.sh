#!/bin/bash -
# Copyright (C) 2010-2014 Red Hat Inc.
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

# The PHP test script cleans the environment.  (This is, apparently,
# to fully simulate how PHP runs when it runs in the context of
# Apache, and not only because PHP is written by morons).  We
# therefore have to load the environment (from php/extension/env which
# is generated below) at the start of each test script.

# As a consequence of above, LIBGUESTFS_DEBUG=1 and LIBGUESTFS_TRACE=1
# won't get passed down to the script.  Furthermore, setting debug or
# trace isn't very useful anyway because the PHP test script mixes
# stdout and stderr together and compares this to the expected output,
# so you'd just get failures for every test.  So there is no good way
# to debug libguestfs failures in PHP tests, but if an individual test
# fails locally then you can edit the guestfs_php_*.phpt.in and
# uncomment the putenv statement, then look at the output.

unset LIBGUESTFS_DEBUG
unset LIBGUESTFS_TRACE

# This makes a file containing the environment variables we want to set.
rm -f env
echo "PATH=$PATH" > env
printenv | grep -E '^(LIBGUESTFS|LIBVIRT|LIBVIRTD|VIRTLOCKD|LD|MALLOC)_' >> env

TESTS=$(echo tests/guestfs_php_*.phpt)
echo TESTS: $TESTS

make test TESTS="$TESTS" PHP_EXECUTABLE="$PWD/php-for-tests.sh" REPORT_EXIT_STATUS=1 TEST_TIMEOUT=300
