#!/bin/bash -
# libguestfs
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

# Test the ntfscat-i command.

set -e

if [ -n "$SKIP_TEST_NTFSCAT_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

rm -f test-mft.bin

# Skip if ntfs-3g is not supported by the appliance.
if ! guestfish add /dev/null : run : available "ntfs3g"; then
    echo "$0: skipped because ntfs-3g is not supported by the appliance"
    exit 77
fi

if [ ! -s ../../test-data/phony-guests/windows.img ]; then
    echo "$0: skipped because windows.img is zero-sized"
    exit 77
fi

# download Master File Table ($MFT).
guestfish --ro -a ../../test-data/phony-guests/windows.img <<EOF
run
ntfscat-i /dev/sda2 0 test-mft.bin
EOF

# test extracted file is the Master File Table
if [ `head -c 5 test-mft.bin` != "FILE0" ]; then
    echo "$0: wrong file extracted."
    exit 1
fi

rm -f test-mft.bin
