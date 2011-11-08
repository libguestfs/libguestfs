#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

rm -f test1.img test2.img test3.img

truncate -s 100M test1.img
test1_md5sum="$(md5sum test1.img | awk '{print $1}')"
truncate -s 100M test2.img
test2_md5sum="$(md5sum test2.img | awk '{print $1}')"
qemu-img create -f qcow2 test3.img 100M
test3_md5sum="$(md5sum test3.img | awk '{print $1}')"

# The vitally important calls are 'add-drive-ro' and
# 'add-drive-opts ... readonly:true'.
../fish/guestfish <<'EOF'
add-drive-ro test1.img
add-drive-opts test2.img format:raw readonly:true
add-drive-opts test3.img format:qcow2 readonly:true
run

part-disk /dev/sda mbr
part-disk /dev/sdb mbr
part-disk /dev/sdc mbr

mkfs ext2 /dev/sda1
copy-size /dev/sda1 /dev/sdb1 5M
pvcreate /dev/sdc1
vgcreate VG /dev/sdc1
lvcreate LV VG 80
mkfs ext3 /dev/VG/LV

mkmountpoint /a
mount-options "" /dev/sda1 /a
mkmountpoint /b
mount-options "" /dev/sdb1 /b
mkmountpoint /c
mount-options "" /dev/VG/LV /c

write /a/test "This is a test"
write /b/test "This is a test"
write /c/test "This is a test"

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
    echo "qemu's snapshot isolation does not appear to be working."
    echo "Running libguestfs could cause disk corruption on live guests."
    echo
    echo "DO NOT USE libguestfs before you have resolved this problem."
    echo
    exit 1
}

if [ "$(md5sum test1.img | awk '{print $1}')" != "$test1_md5sum" ]; then
    serious_error
fi
if [ "$(md5sum test2.img | awk '{print $1}')" != "$test2_md5sum" ]; then
    serious_error
fi
if [ "$(md5sum test3.img | awk '{print $1}')" != "$test3_md5sum" ]; then
    serious_error
fi

rm test1.img test2.img test3.img
