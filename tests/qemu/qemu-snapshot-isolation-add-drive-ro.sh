#!/bin/bash -
# libguestfs
# Copyright (C) 2011-2023 Red Hat Inc.
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

# Test that qemu snapshots are really isolating writes from the
# underlying disk image.  If this test were to fail, you could expect
# libguestfs to cause massive disk corruption on live guests.

set -e

$TEST_FUNCTIONS
skip_if_skipped

f=isolation-add-drive-ro.img
rm -f $f

guestfish sparse $f 100M
md5sum="$(do_md5 $f)"

guestfish <<EOF
add-drive-ro $f

run

# Read some of the backing file to ensure reads don't modify it.
download-offset /dev/sda - 10M 10M | cat >/dev/null

part-disk /dev/sda mbr
mkfs ext2 /dev/sda1
mount /dev/sda1 /
write /test This_is_a_test
fill-pattern abc 5M /test2

# Really try hard to force writes to the disk.
umount-all
sync

EOF

# Now verify that the original disks have not been touched.
function serious_error
{
    echo
    echo
    echo "***** SERIOUS ERROR *****"
    echo "qemu’s snapshot isolation does not appear to be working."
    echo "Running libguestfs could cause disk corruption on live guests."
    echo
    echo "DO NOT USE libguestfs before you have resolved this problem."
    echo
    exit 1
}

if [ "$(do_md5 $f)" != "$md5sum" ]; then
    serious_error
fi

rm $f
