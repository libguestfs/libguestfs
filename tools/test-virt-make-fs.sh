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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

export LANG=C
set -e

# Is NTFS supported?
if ../fish/guestfish -a /dev/null run : available "ntfs3g ntfsprogs"; then
  ntfs_supported=yes
else
  ntfs_supported=no
fi

# Engage in some montecarlo testing of virt-make-fs.

if [ "$ntfs_supported" = "yes" ]; then
  case $((RANDOM % 4)) in
      0) type="--type=ext2" ;;
      1) type="--type=ext3" ;;
      2) type="--type=ext4" ;;
      3) type="--type=ntfs" ;;
      # Can't test vfat because we cannot create a tar archive
      # where files are owned by UID:GID 0:0.  As a result, tar
      # in the appliance fails when trying to change the UID of
      # the files to some non-zero value (not supported by FAT).
      # 4) type="--type=vfat" ;;
  esac
else
  case $((RANDOM % 3)) in
      0) type="--type=ext2" ;;
      1) type="--type=ext3" ;;
      2) type="--type=ext4" ;;
  esac
fi

case $((RANDOM % 2)) in
    0) format="--format=raw" ;;
    1) format="--format=qcow2" ;;
esac

case $((RANDOM % 3)) in
    0) partition="--partition" ;;
    1) partition="--partition=gpt" ;;
    2) ;;
esac

case $((RANDOM % 2)) in
    0) ;;
    1) size="--size=+1M" ;;
esac

if [ -n "$LIBGUESTFS_DEBUG" ]; then debug=--debug; fi

params="$type $format $partition $size $debug"
echo "test-virt-make-fs: parameters: $params"

rm -f test.file test.tar output.img

tarsize=$((RANDOM & 8191))
echo "test-virt-make-fs: size of test file: $tarsize KB"
dd if=/dev/zero of=test.file bs=1024 count=$tarsize
tar -c -f test.tar test.file
rm test.file

./virt-make-fs $params -- test.tar output.img

rm test.tar output.img
