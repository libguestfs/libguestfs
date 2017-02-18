#!/bin/bash -
# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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
# https://bugzilla.redhat.com/show_bug.cgi?id=1174551
# check that list-alike APIs accept only relative paths and reject
# absolute ones

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest fedora.img

rm -f test.error

$VG guestfish \
    --ro --format=raw -a $top_builddir/test-data/phony-guests/fedora.img \
    -i <<EOF 2>test.error
# valid invocations
lstatlist /etc "fedora-release sysconfig"
lstatnslist /etc "fedora-release sysconfig"
readlinklist /bin "test5"

# invalid invocations
-lstatlist / "/bin"
-lstatnslist / "/bin"
-lstatlist /etc "../bin sysconfig/network"
-readlinklist /etc "/bin/test5"
EOF

# check the number of errors in the log
if [ $(grep '^\*stdin\*.*is not a file name' test.error | wc -l) -ne 4 ]; then
    echo "$0: unexpected errors in the log:"
    cat test.error
    exit 1
fi

rm test.error
