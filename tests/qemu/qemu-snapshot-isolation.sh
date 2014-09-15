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

# UML backend doesn't support qcow2 format.
supports_qcow2=yes
if [ "$(guestfish get-backend)" = "uml" ]; then
    supports_qcow2=no
fi

rm -f isolation1.img isolation2.img isolation3.img

guestfish sparse isolation1.img 100M
isolation1_md5sum="$(md5sum isolation1.img | awk '{print $1}')"
guestfish sparse isolation2.img 100M
isolation2_md5sum="$(md5sum isolation2.img | awk '{print $1}')"

if [ "$supports_qcow2" = "yes" ]; then
    guestfish \
        disk-create isolation3.img qcow2 100M preallocation:metadata
    isolation3_md5sum="$(md5sum isolation3.img | awk '{print $1}')"
    add3="add-drive-opts isolation3.img format:qcow2 readonly:true"
    cmds3="
      part-disk /dev/sdc mbr
      mkfs ext2 /dev/sdc1
      mkmountpoint /c
      mount /dev/sdc1 /c
      write /c/test This_is_a_test
    "
fi

# The vitally important calls are 'add-drive-ro' and
# 'add-drive-opts ... readonly:true'.
guestfish <<EOF
add-drive-ro isolation1.img
add-drive-opts isolation2.img format:raw readonly:true
$add3

run

part-disk /dev/sda mbr
mkfs ext2 /dev/sda1
mkmountpoint /a
mount /dev/sda1 /a
write /a/test This_is_a_test

part-disk /dev/sdb mbr
mkfs ext2 /dev/sdb1
mkmountpoint /b
mount /dev/sdb1 /b
write /b/test This_is_a_test

$cmds3

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

if [ "$(md5sum isolation1.img | awk '{print $1}')" != "$isolation1_md5sum" ]; then
    serious_error
fi
if [ "$(md5sum isolation2.img | awk '{print $1}')" != "$isolation2_md5sum" ]; then
    serious_error
fi
if [ "$supports_qcow2" = "yes" -a \
     "$(md5sum isolation3.img | awk '{print $1}')" != "$isolation3_md5sum" ]; then
    serious_error
fi

rm isolation1.img isolation2.img
if [ "$supports_qcow2" = "yes" ]; then
    rm isolation3.img
fi
