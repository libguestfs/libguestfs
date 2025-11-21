#!/bin/bash -
# libguestfs
# Copyright Red Hat
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

# Test btrfs subvolumes and snapshots.

source ./functions.sh
set -e
set -x

skip_if_skipped
skip_unless_feature_available btrfs

guestfish <<'EOF'

# Create a large empty disk.
sparse test-btrfs-subvolume-snapshot.img 10G
run

mkfs btrfs /dev/sda
mount /dev/sda /

# Create some subvolumes.
btrfs-subvolume-create /sub0
btrfs-subvolume-create /sub1
btrfs-subvolume-create /sub3

# Create a few snapshots.
btrfs-subvolume-snapshot /sub1 /snap11
btrfs-subvolume-snapshot /sub3 /snap31
btrfs-subvolume-snapshot /sub3 /snap3123
btrfs-subvolume-snapshot /sub3 /snap3123456123456

# List the subvolumes.
btrfs-subvolume-show /sub0
btrfs-subvolume-show /sub1
btrfs-subvolume-show /sub3

# Capture the list of snapshots.
btrfs-subvolume-show /sub0 | grep -F 'Snapshot(s):'  > subvolume-snapshot.out
btrfs-subvolume-show /sub1 | grep -F 'Snapshot(s):' >> subvolume-snapshot.out
btrfs-subvolume-show /sub3 | grep -F 'Snapshot(s):' >> subvolume-snapshot.out

EOF

cat subvolume-snapshot.out

test "$(cat subvolume-snapshot.out)" = \
     "Snapshot(s): 
Snapshot(s): snap11
Snapshot(s): snap31,snap3123,snap3123456123456"

rm test-btrfs-subvolume-snapshot.img subvolume-snapshot.out
