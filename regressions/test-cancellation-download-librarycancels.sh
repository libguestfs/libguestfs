#!/bin/bash -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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

# Test download where the library cancels.
#
# Download big and small files to /dev/full.  This should fail but not
# kill the appliance.  We test various randomized file sizes because
# there are many potential race conditions -- for example the daemon
# may or may not send all of its data because the error condition is
# detected.

set -e

rm -f test.img

size=$(awk 'BEGIN{ srand(); print int(16*1024*rand()) }')
echo "$0: test size $size (bytes)"

../fish/guestfish <<EOF
# We want the file to be fully allocated.
alloc test.img 10M
run

part-disk /dev/sda mbr
mkfs ext2 /dev/sda1
mount-options "" /dev/sda1 /

fallocate64 /file $size

# Download the file into /dev/full so it fails.
-download /file /dev/full

# The daemon should still be reachable after the failure.
ping-daemon

EOF

rm -f test.img
