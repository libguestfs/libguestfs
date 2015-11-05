#!/bin/bash -
# libguestfs
# Copyright (C) 2015 Fujitsu Inc.
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

# Test btrfs replace devices.

set -e

# Allow the test to be skipped since btrfs is often broken.
if [ -n "$SKIP_TEST_BTRFS_REPLACE_SH" ]; then
    echo "$0: skipping test because environment variable is set."
    exit 77
fi

# If btrfs is not available, bail.
if ! guestfish -a /dev/null run : available btrfs; then
    echo "$0: skipping test because btrfs is not available"
    exit 77
fi

rm -f test-btrfs-replace-{1,2}.img replace.output

guestfish  <<EOF > replace.output
# Add 2 empty disks
sparse test-btrfs-replace-1.img 1G
sparse test-btrfs-replace-2.img 1G
run

mkfs-btrfs /dev/sda
mount /dev/sda /

mkdir /data
copy-in $srcdir/../../test-data/files/filesanddirs-10M.tar.xz /data

# now, sda is btrfs while sdb is blank.
btrfs-replace /dev/sda /dev/sdb /

# after replace: sda is wiped out, while sdb has btrfs with data
list-filesystems
ls /data/

EOF

if [ "$(cat replace.output)" != "/dev/sda: unknown
/dev/sdb: btrfs
filesanddirs-10M.tar.xz" ]; then
    echo "btrfs-repalce fail!"
    cat replace.output
    exit 1
fi

rm test-btrfs-replace-{1,2}.img replace.output
