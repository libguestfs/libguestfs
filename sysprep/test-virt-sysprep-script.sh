#!/bin/bash -
# libguestfs virt-sysprep test --script option
# Copyright (C) 2011-2012 Red Hat Inc.
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

export LANG=C
set -e
#set -x

if [ -n "$SKIP_TEST_VIRT_SYSPREP_SCRIPT_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 0
fi

if [ ! -w /dev/fuse ]; then
    echo "$0: SKIPPING test, because there is no /dev/fuse."
    exit 0
fi

# Check that multiple scripts can run.
rm -f stamp-script1.sh stamp-script2.sh
if ! ./virt-sysprep -q -n -a ../tests/guests/fedora.img --enable script \
        --script $abs_srcdir/script1.sh --script $abs_srcdir/script2.sh; then
    echo "$0: virt-sysprep wasn't expected to exit with error."
    exit 1
fi
if [ ! -f stamp-script1.sh -o ! -f stamp-script2.sh ]; then
    echo "$0: one of the two test scripts did not run."
    exit 1
fi

# Check that if a script fails, virt-sysprep exits with an error.
if ./virt-sysprep -q -n -a ../tests/guests/fedora.img --enable script \
        --script $abs_srcdir/script3.sh; then
    echo "$0: virt-sysprep didn't exit with an error."
    exit 1
fi
