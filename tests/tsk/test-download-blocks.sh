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

# Test the download_blocks command.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available sleuthkit
skip_unless_phony_guest blank-fs.img

rm -f test-download-blocks.bin

# Download Master File Table ($MFT).
guestfish --ro -a $top_builddir/test-data/phony-guests/blank-fs.img <<EOF
run
mount /dev/sda1 /
write /test.txt "$foo$bar$"
rm /test.txt
umount /
download-blocks /dev/sda1 0 8192 test-download-blocks.bin unallocated:true
EOF

# test extracted data contains $foo$bar$ string
grep -q "$foo$bar$" test-download-blocks.bin
if [ $? neq 0 ]; then
    echo "$0: removed data not found."
    exit 1
fi

rm -f test-download-blocks.bin
