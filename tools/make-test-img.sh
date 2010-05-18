#!/bin/bash -
# libguestfs virt-* tools
# Copyright (C) 2010 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Make a standard test image which is used by all the tools/test-*.sh
# test scripts.  This test image is supposed to look like a Fedora
# installation, or at least enough of one to fool virt-inspector's
# heuristics.

export LANG=C
set -e

rm -f test.img

cat > fstab <<EOF
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF

# Create a disk image.
../fish/guestfish <<'EOF'
sparse test.img- 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64     524287
part-add /dev/sda p 524288    -64

pvcreate /dev/sda2
vgcreate VG /dev/sda2
lvcreate Root VG 32
lvcreate LV1 VG 32
lvcreate LV2 VG 32
lvcreate LV3 VG 64

# Phony /boot filesystem.
mkfs-b ext2 4096 /dev/sda1
set-e2label /dev/sda1 BOOT

# Phony root filesystem.
mkfs-b ext2 4096 /dev/VG/Root
set-e2label /dev/VG/Root ROOT

# Enough to fool virt-inspector.
mount-options "" /dev/VG/Root /
mkdir /boot
mount-options "" /dev/sda1 /boot
mkdir /bin
mkdir /etc
mkdir /usr
upload fstab /etc/fstab
mkdir /boot/grub
touch /boot/grub/grub.conf

# Test files.
write /etc/test1 "abcdefg"
write /etc/test2 ""
write /bin/test1 "abcdefg"
write /bin/test2 "zxcvbnm"
write /bin/test3 "1234567"
write /bin/test4 ""
ln-s /bin/test1 /bin/test5
mkfifo 0777 /bin/test6
mknod 0777 10 10 /bin/test7

# Other filesystems.
# Note that these should be empty, for testing virt-df.
mkfs-b ext2 4096 /dev/VG/LV1
mkfs-b ext2 1024 /dev/VG/LV2
mkfs-b ext2 2048 /dev/VG/LV3
EOF

rm fstab
mv test.img- test.img
