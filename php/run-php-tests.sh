#!/bin/bash -
# Copyright (C) 2010-2023 Red Hat Inc.
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

# This makes a file containing the environment variables we want to set.
rm -f env
echo "PATH=$PATH" > env
printenv | grep -E '^(LIBGUESTFS|LIBVIRT|LIBVIRTD|VIRTLOCKD|LD|MALLOC)_' >> env

TESTS=$(echo tests/guestfs_*.phpt)
echo TESTS: $TESTS

${MAKE:-make} test TESTS="$TESTS" PHP_EXECUTABLE="$PWD/php-for-tests.sh" REPORT_EXIT_STATUS=1 TEST_TIMEOUT=300
