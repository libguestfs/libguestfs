#!/bin/bash -
# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Make an Arch Linux image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# Create a disk image.
guestfish <<EOF
sparse archlinux.img-t 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64	    -64

# Phony / filesystem.
mkfs ext4 /dev/sda1 blocksize:4096
set-e2uuid /dev/sda1 01234567-0123-0123-0123-012345678902

# Enough to fool inspection API.
mount /dev/sda1 /
mkdir /boot
mkdir /bin
mkdir /etc
mkdir /home
mkdir /usr
mkdir-p /var/lib/pacman/local/test-package-1:0.1-1

write /etc/fstab "/dev/sda1 / ext4 rw,relatime,data=ordered 0 1"
touch /etc/arch-release
write /etc/hostname "archlinux.test"

upload $SRCDIR/archlinux-package /var/lib/pacman/local/test-package-1:0.1-1/desc

upload $SRCDIR/../binaries/bin-x86_64-dynamic /bin/ls

mkdir /boot/grub
touch /boot/grub/grub.conf
EOF

mv archlinux.img-t archlinux.img
