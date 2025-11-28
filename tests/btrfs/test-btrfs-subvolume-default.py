#!/usr/bin/env python3
# libguestfs
# Copyright (C) 2025 Red Hat Inc.
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

# Test btrfs subvolume list and btrfs subvolume default-id.

import sys
import os
import guestfs

# Allow the test to be skipped since btrfs is often broken.
if 'SKIP_TEST_BTRFS_SUBVOLUME_DEFAULT_PY' in os.environ:
    sys.exit(77)

g = guestfs.GuestFS()
g.add_drive_scratch(1024 * 1024 * 1024)
g.launch()

# If btrfs is not available, bail.
if not g.feature_available(["btrfs"]):
    print(f"{sys.argv[0]}: skipping test because btrfs is not available", file=sys.stderr)
    sys.exit(77)

g.part_disk("/dev/sda", "mbr")
g.mkfs_btrfs(["/dev/sda1"])
g.mount("/dev/sda1", "/")
g.btrfs_subvolume_create("/test1")
g.mkdir("/test1/foo")
g.btrfs_subvolume_create("/test2")
vols = g.btrfs_subvolume_list("/")
# Check the subvolume list, and extract the subvolume ID of path 'test1',
# and the top level ID (which should be the same for both subvolumes).
if len(vols) != 2:
    raise Exception("expected 2 subvolumes, but got {} instead".format(len(vols)))
ids = {}
top_level_id = None
for vol in vols:
    path = vol['btrfssubvolume_path']
    id_ = vol['btrfssubvolume_id']
    top = vol['btrfssubvolume_top_level_id']
    if top_level_id is None:
        top_level_id = top
    elif top_level_id != top:
        raise Exception("top_level_id fields are not all the same")
    ids[path] = id_
if 'test1' not in ids:
    raise Exception("no subvolume path 'test1' found")
test1_id = ids['test1']
g.btrfs_subvolume_set_default(test1_id, "/")
g.umount("/")
g.mount("/dev/sda1", "/")
# This was originally /test1/foo, but now that we changed the
# default ID to 'test1', /test1 is mounted as /, so:
g.mkdir("/foo/bar")
g.btrfs_subvolume_set_default(top_level_id, "/")
g.umount("/")
g.mount("/dev/sda1", "/")
# Now we're back to the original default volume, so this should work:
g.mkdir("/test1/foo/bar/baz")
g.shutdown()
g.close()
