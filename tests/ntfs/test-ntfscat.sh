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

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available ntfs3g
skip_unless_phony_guest windows.img

rm -f test-mft.bin

# Download Master File Table ($MFT).
guestfish \
    --ro --format=raw -a $top_builddir/test-data/phony-guests/windows.img <<EOF
run
ntfscat-i /dev/sda2 0 test-mft.bin
EOF

# test extracted file is the Master File Table
if [ `head -c 5 test-mft.bin` != "FILE0" ]; then
    echo "$0: wrong file extracted."
    exit 1
fi

rm -f test-mft.bin
