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

# Miscellaneous xfs features.

import sys
import os
import guestfs

if 'SKIP_TEST_XFS_MISC_PY' in os.environ:
    sys.exit(77)

g = guestfs.GuestFS()
g.add_drive_scratch(1024 * 1024 * 1024)
g.launch()

# If xfs is not available, bail.
if not g.feature_available(["xfs"]):
    print("{}: skipping test because xfs is not available".format(sys.argv[0]), file=sys.stderr)
    sys.exit(77)

g.part_disk("/dev/sda", "mbr")
g.mkfs("xfs", "/dev/sda1")

# Setting label.
g.set_label("/dev/sda1", "newlabel")
label = g.vfs_label("/dev/sda1")
if label != "newlabel":
    raise Exception("unexpected label: expecting 'newlabel' but got '{}'".format(label))

# Setting UUID.
newuuid = "01234567-0123-0123-0123-0123456789ab"
g.set_uuid("/dev/sda1", newuuid)
uuid = g.vfs_uuid("/dev/sda1")
if uuid != newuuid:
    raise Exception("unexpected UUID: expecting '{}' but got '{}'".format(newuuid, uuid))

g.shutdown()
g.close()
