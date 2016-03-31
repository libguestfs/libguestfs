#!/bin/bash -
# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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

# Make a CoreOS image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# os-release file.
cat > coreos.release <<'EOF'
NAME=CoreOS
ID=coreos
VERSION=899.13.0
VERSION_ID=899.13.0
BUILD_ID=2016-03-23-0120
PRETTY_NAME="CoreOS 899.13.0"
ANSI_COLOR="1;32"
HOME_URL="https://coreos.com/"
BUG_REPORT_URL="https://github.com/coreos/bugs/issues"
EOF

# Create a disk image.
guestfish <<EOF
sparse coreos.img-t 512M
run

part-init /dev/sda gpt
part-add /dev/sda p 4096 266239
part-add /dev/sda p 266240 270335
part-add /dev/sda p 270336 532479
part-add /dev/sda p 532480 794623
part-add /dev/sda p 794624 -4096

part-set-name /dev/sda 1 EFI_SYSTEM
part-set-bootable /dev/sda 1 true
part-set-name /dev/sda 2 BIOS-BOOT
part-set-name /dev/sda 3 USR-A
part-set-name /dev/sda 4 USR-B
part-set-name /dev/sda 5 ROOT

mkfs fat /dev/sda1
mkfs ext4 /dev/sda3
set-label /dev/sda3 USR-A
set-uuid /dev/sda3 01234567-0123-0123-0123-012345678901
mkfs ext4 /dev/sda5
set-label /dev/sda5 ROOT
set-uuid /dev/sda5 01234567-0123-0123-0123-012345678902

# Enough to fool inspection API.
mount /dev/sda5 /
mkdir-p /etc/coreos
mkdir /usr
mount /dev/sda3 /usr
mkdir /usr/bin
mkdir /usr/lib64
mkdir /usr/local
mkdir-p /usr/share/coreos/

ln-s usr/bin /bin
ln-s usr/lib64 /lib64
ln-s lib64 /lib
ln-s lib64 /usr/lib
mkdir /root
mkdir /home

write /etc/coreos/update.conf "GROUP=stable"
upload coreos.release /usr/lib/os-release
ln-s ../usr/lib/os-release /etc/os-release
write /etc/hostname "coreos.invalid"

EOF

rm coreos.release
mv coreos.img-t coreos.img
