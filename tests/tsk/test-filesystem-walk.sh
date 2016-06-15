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

# Test the filesystem-walk command.

if [ -n "$SKIP_TEST_FILESYSTEM_WALK_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

# Skip if TSK is not supported by the appliance.
if ! guestfish add /dev/null : run : available "libtsk"; then
    echo "$0: skipped because TSK is not available in the appliance"
    exit 77
fi

if [ ! -s ../../test-data/phony-guests/windows.img ]; then
    echo "$0: skipped because windows.img is zero-sized"
    exit 77
fi

output=$(
guestfish --ro -a ../../test-data/phony-guests/windows.img <<EOF
run
mount /dev/sda2 /
write /test.txt "foobar"
rm /test.txt
umount /
filesystem-walk /dev/sda2
EOF
)

# test $MFT is in the list
echo $output | grep -zq '{ tsk_inode: 0
tsk_type: r
tsk_size: .*
tsk_name: \$MFT
tsk_flags: 1
tsk_spare1: 0
tsk_spare2: 0
tsk_spare3: 0
tsk_spare4: 0
tsk_spare5: 0 }'
if [ $? != 0 ]; then
    echo "$0: \$MFT not found in files list."
    echo "File list:"
    echo $output
    exit 1
fi

# test deleted file is in the list
echo $output | grep -zq '{ tsk_inode: .*
tsk_type: [ru]
tsk_size: .*
tsk_name: test.txt
tsk_flags: 0
tsk_spare1: 0
tsk_spare2: 0
tsk_spare3: 0
tsk_spare4: 0
tsk_spare5: 0 }'
if [ $? != 0 ]; then
    echo "$0: /test.txt not found in files list."
    echo "File list:"
    echo $output
    exit 1
fi
