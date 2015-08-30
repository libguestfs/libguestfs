#!/bin/bash -
# libguestfs
# Copyright (C) 2010-2016 Red Hat Inc.
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

# Make a Windows image which is enough to fool the inspection heuristics.

export LANG=C
set -e

# If the currently compiled libguestfs doesn't support
# ntfs-3g/ntfsprogs then we cannot create a Windows phony image.
# Nothing actually uses windows.img in the standard build so we can
# just 'touch' it and emit a warning.
if ! guestfish -a /dev/null run : available "ntfs3g ntfsprogs"; then
  echo "***"
  echo "Warning: cannot create windows.img because there is no NTFS"
  echo "support in this build of libguestfs.  Just touching the output"
  echo "file instead."
  echo "***"
  touch windows.img
  exit 0
fi

# Create a disk image.
guestfish <<EOF
set-program virt-testing
sparse windows.img-t 512M
run

# Format the disk.
part-init /dev/sda mbr
part-add /dev/sda p 64     524287
part-add /dev/sda p 524288    -64

# Disk ID.
pwrite-device /dev/sda "1234" 0x01b8 | cat >/dev/null

# Phony boot loader filesystem.
mkfs ntfs /dev/sda1

# Phony root filesystem.
mkfs ntfs /dev/sda2

# Enough to fool inspection API.
mount /dev/sda2 /
mkdir-p /Windows/System32/Config
mkdir-p /Windows/System32/Drivers

upload $SRCDIR/windows-software /Windows/System32/Config/SOFTWARE
upload $SRCDIR/windows-system /Windows/System32/Config/SYSTEM

upload $SRCDIR/../binaries/bin-win32.exe /Windows/System32/cmd.exe

mkdir "/Program Files"
touch /autoexec.bat

EOF

mv windows.img-t windows.img
