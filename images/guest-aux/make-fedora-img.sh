#!/bin/bash -
# libguestfs
# Copyright (C) 2010-2011 Red Hat Inc.
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

# Make a standard test image which is used by all the tools test
# scripts.  This test image is supposed to look like a Fedora
# installation, or at least enough of one to fool the inspection API
# heuristics.

export LANG=C
set -e

# fstab file.
cat > fstab.tmp <<EOF
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF

# Create a disk image.
../run ../fish/guestfish <<EOF
sparse fedora.img.tmp 512M
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
mkfs-opts ext2 /dev/sda1 blocksize:4096
set-e2label /dev/sda1 BOOT
set-e2uuid /dev/sda1 01234567-0123-0123-0123-012345678901

# Phony root filesystem.
mkfs-opts ext2 /dev/VG/Root blocksize:4096
set-e2label /dev/VG/Root ROOT
set-e2uuid /dev/VG/Root 01234567-0123-0123-0123-012345678902

# Enough to fool inspection API.
mount-options "" /dev/VG/Root /
mkdir /boot
mount-options "" /dev/sda1 /boot
mkdir /bin
mkdir /etc
mkdir /etc/sysconfig
mkdir /usr
mkdir-p /var/lib/rpm

upload fstab.tmp /etc/fstab
write /etc/redhat-release "Fedora release 14 (Phony)"
write /etc/fedora-release "Fedora release 14 (Phony)"
write /etc/sysconfig/network "HOSTNAME=fedora.invalid"

upload guest-aux/fedora-name.db /var/lib/rpm/Name
upload guest-aux/fedora-packages.db /var/lib/rpm/Packages

upload ${SRCDIR}/bin-x86_64-dynamic /bin/ls

mkdir /boot/grub
touch /boot/grub/grub.conf

# Test files.
write /etc/test1 "abcdefg"
write /etc/test2 ""
upload -<<__end /etc/test3
a
b
c
d
e
f
__end
write /bin/test1 "abcdefg"
write /bin/test2 "zxcvbnm"
write /bin/test3 "1234567"
write /bin/test4 ""
ln-s /bin/test1 /bin/test5
mkfifo 0777 /bin/test6
mknod 0777 10 10 /bin/test7

# Other filesystems.
# Note that these should be empty, for testing virt-df.
mkfs-opts ext2 /dev/VG/LV1 blocksize:4096
mkfs-opts ext2 /dev/VG/LV2 blocksize:1024
mkfs-opts ext2 /dev/VG/LV3 blocksize:2048
EOF

rm fstab.tmp
mv fedora.img.tmp fedora.img
