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

# Make a Windows image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# Create a disk image.
../fish/guestfish <<'EOF'
sparse windows.img.tmp 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64     524287
part-add /dev/sda p 524288    -64

# Phony boot loader filesystem.
mkfs ntfs /dev/sda1

# Phony root filesystem.
mkfs ntfs /dev/sda2

# Enough to fool inspection API.
mount-options "" /dev/sda2 /
mkdir-p /Windows/System32/Config

upload guest-aux/windows-software /Windows/System32/Config/SOFTWARE
upload guest-aux/windows-system /Windows/System32/Config/SYSTEM

upload bin-win32.exe /Windows/System32/cmd.exe

mkdir "/Program Files"
touch /autoexec.bat

EOF

mv windows.img.tmp windows.img
