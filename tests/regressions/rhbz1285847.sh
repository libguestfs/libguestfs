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

# Regression test for virt-resize handling of logical volumes
# https://bugzilla.redhat.com/1285847

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ1285847_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if ! ../../resize/virt-resize --help >/dev/null 2>&1; then
    echo "$0: test skipped because virt-resize was not built"
    exit 77
fi

rm -f rhbz1285847.img rhbz1285847-2.img rhbz1285847.out

# Create a disk with logical volumes.
guestfish <<EOF
  sparse rhbz1285847.img 4G
  run
  part-init /dev/sda mbr
  # This partition layout is copied from the Ubuntu 14.04
  # virt-builder template.
  part-add /dev/sda p $((1048576/512))    $(((3221225471+1)/512))
  part-add /dev/sda e $((3222273024/512)) $(((4293918719+1)/512))
  part-add /dev/sda l $((3222274048/512)) $(((4293918719+1)/512))

  mkfs ext4 /dev/sda1
  mkswap /dev/sda5

  echo "Partitions before resizing:"
  part-list /dev/sda

  echo "Filesystems before resizing:"
  list-filesystems
EOF

truncate -s 10G rhbz1285847-2.img
virt-resize rhbz1285847.img rhbz1285847-2.img --expand /dev/sda2

# Check that the filesystems made it across.
guestfish -a rhbz1285847-2.img run : list-filesystems > rhbz1285847.out

if [ "$(cat rhbz1285847.out)" != "/dev/sda1: ext4
/dev/sda2: unknown
/dev/sda5: swap" ]; then
    echo "$0: unexpected result:"
    cat rhbz1285847.out
    exit 1
fi

rm rhbz1285847.img rhbz1285847-2.img rhbz1285847.out
