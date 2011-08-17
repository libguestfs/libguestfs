#!/bin/bash -
# libguestfs
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

# Make a Debian image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# fstab file.
cat > fstab.tmp <<EOF
LABEL=BOOT /boot ext2 default 0 0
/dev/debian/root / ext2 default 0 0
/dev/debian/usr /usr ext2 default 1 2
/dev/debian/var /var ext2 default 1 2
/dev/debian/home /home ext2 default 1 2
EOF

# Create a disk image.
../run ../fish/guestfish <<EOF
sparse debian.img.tmp 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64     524287
part-add /dev/sda p 524288    -64

pvcreate /dev/sda2
vgcreate debian /dev/sda2
lvcreate root debian 64
lvcreate usr debian 32
lvcreate var debian 32
lvcreate home debian 32

# Phony /boot filesystem.
mkfs-opts ext2 /dev/sda1 blocksize:4096
set-e2label /dev/sda1 BOOT
set-e2uuid /dev/sda1 01234567-0123-0123-0123-012345678901

# Phony root and other filesystems.
mkfs-opts ext2 /dev/debian/root blocksize:4096
set-e2uuid /dev/debian/root 01234567-0123-0123-0123-012345678902
mkfs-opts ext2 /dev/debian/usr blocksize:4096
set-e2uuid /dev/debian/usr 01234567-0123-0123-0123-012345678903
mkfs-opts ext2 /dev/debian/var blocksize:4096
set-e2uuid /dev/debian/var 01234567-0123-0123-0123-012345678904
mkfs-opts ext2 /dev/debian/home blocksize:4096
set-e2uuid /dev/debian/home 01234567-0123-0123-0123-012345678905

# Enough to fool inspection API.
mount-options "" /dev/debian/root /
mkdir /boot
mount-options "" /dev/sda1 /boot
mkdir /usr
mount-options "" /dev/debian/usr /usr
mkdir /var
mount-options "" /dev/debian/var /var
mkdir /home
mount-options "" /dev/debian/home /home
mkdir /bin
mkdir /etc
mkdir-p /var/lib/dpkg

upload fstab.tmp /etc/fstab
write /etc/debian_version "5.0.1"
write /etc/hostname "debian.invalid"

upload ${SRCDIR}/guest-aux/debian-packages /var/lib/dpkg/status

upload ${SRCDIR}/bin-x86_64-dynamic /bin/ls

mkdir /boot/grub
touch /boot/grub/grub.conf
EOF

rm fstab.tmp
mv debian.img.tmp debian.img
