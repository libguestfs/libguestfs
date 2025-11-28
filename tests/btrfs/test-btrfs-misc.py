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

# Miscellaneous btrfs features.

import sys
import os
import errno
import guestfs

# Allow the test to be skipped since btrfs is often broken.
if 'SKIP_TEST_BTRFS_MISC_PY' in os.environ:
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

# Setting label.
g.set_label("/dev/sda1", "newlabel")
label = g.vfs_label("/dev/sda1")
if label != "newlabel":
    raise Exception("unexpected label: expecting 'newlabel' but got '{}'".format(label))

# Setting btrfs UUID
try:
    g.set_uuid("/dev/sda1", "12345678-1234-1234-1234-123456789012")
except RuntimeError:
    err = g.last_errno()
    if err == errno.ENOTSUP:
        print("$0: skipping test for btrfs UUID change feature is not available", file=sys.stderr)
    else:
        raise
else:
    uuid = g.vfs_uuid("/dev/sda1")
    if uuid != "12345678-1234-1234-1234-123456789012":
        raise Exception("unexpected uuid expecting '12345678-1234-1234-1234-123456789012' but got '{}'".format(uuid))

# Setting btrfs random UUID.
try:
    g.set_uuid_random("/dev/sda1")
except RuntimeError:
    err = g.last_errno()
    if err == errno.ENOTSUP:
        print("$0: skipping test for btrfs UUID change feature is not available", file=sys.stderr)
    else:
        raise

g.shutdown()
g.close()
