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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Make an Ubuntu image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# fstab file.
cat > fstab.tmp <<EOF
LABEL=BOOT /boot ext2 default 0 0
/dev/sda2 / ext2 default 1 2
EOF

# lsb-release file.
cat > release.tmp <<'EOF'
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=10.10
DISTRIB_CODENAME=maverick
DISTRIB_DESCRIPTION="Ubuntu 10.10 (Phony Pharaoh)"
EOF

# Create a disk image.
../run ../fish/guestfish <<EOF
sparse ubuntu.img.tmp 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64     524287
part-add /dev/sda p 524288    -64

# Phony /boot filesystem.
mkfs-opts ext2 /dev/sda1 blocksize:4096
set-e2label /dev/sda1 BOOT
set-e2uuid /dev/sda1 01234567-0123-0123-0123-012345678901

# Phony root filesystem (Ubuntu doesn't use LVM by default).
mkfs-opts ext2 /dev/sda2 blocksize:4096
set-e2uuid /dev/sda2 01234567-0123-0123-0123-012345678902

# Enough to fool inspection API.
mount-options "" /dev/sda2 /
mkdir /boot
mount-options "" /dev/sda1 /boot
mkdir /bin
mkdir /etc
mkdir /home
mkdir /usr
mkdir-p /var/lib/dpkg

upload fstab.tmp /etc/fstab
write /etc/debian_version "5.0.1"
upload release.tmp /etc/lsb-release
write /etc/hostname "ubuntu.invalid"

upload ${SRCDIR}/guest-aux/debian-packages /var/lib/dpkg/status

upload ${SRCDIR}/bin-x86_64-dynamic /bin/ls

mkdir /boot/grub
touch /boot/grub/grub.conf
EOF

rm fstab.tmp release.tmp
mv ubuntu.img.tmp ubuntu.img
