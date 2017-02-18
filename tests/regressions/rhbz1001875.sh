#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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
# https://bugzilla.redhat.com/show_bug.cgi?id=1001875
# tar-out excludes option.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f rhbz1001875.img rhbz1001875-[123].tar

guestfish -N rhbz1001875.img=fs -m /dev/sda1 <<EOF
touch /hello
touch /world
touch /helloworld
tar-out / rhbz1001875-1.tar "excludes:hello"
tar-out / rhbz1001875-2.tar "excludes:hello world"
tar-out / rhbz1001875-3.tar "excludes:he* w*"
EOF

if [ "$(tar tf rhbz1001875-1.tar | sort)" != "./
./helloworld
./lost+found/
./world" ]; then
    echo "$0: unexpected output from #1 test:"
    tar tf rhbz1001875-1.tar | sort
    exit 1
fi

if [ "$(tar tf rhbz1001875-2.tar | sort)" != "./
./helloworld
./lost+found/" ]; then
    echo "$0: unexpected output from #2 test:"
    tar tf rhbz1001875-2.tar | sort
    exit 1
fi

if [ "$(tar tf rhbz1001875-3.tar | sort)" != "./
./lost+found/" ]; then
    echo "$0: unexpected output from #3 test:"
    tar tf rhbz1001875-3.tar | sort
    exit 1
fi

rm rhbz1001875.img rhbz1001875-[123].tar
