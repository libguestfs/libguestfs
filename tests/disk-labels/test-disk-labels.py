#!/usr/bin/env python3
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

# Test using the 'label' option of add_drive, and the
# list_disk_labels call.

import os
import sys
import guestfs

if os.environ.get('SKIP_TEST_DISK_LABELS_PY'):
    sys.exit(77)

# IMPORTANT: use python_return_dict=True so list_disk_labels() returns a Python dict,
# not a list of (label, device) pairs. The checks below assume a dict.
g = guestfs.GuestFS(python_return_dict=True)

# Add two drives.
for label in ["a", "b"]:
    g.add_drive_scratch(512 * 1024 * 1024, label=label)

g.launch()

# Partition the drives.
g.part_disk("/dev/disk/guestfs/a", "mbr")
g.part_init("/dev/disk/guestfs/b", "mbr")
g.part_add("/dev/disk/guestfs/b", "p", 64, 100 * 1024 * 2 - 1)
g.part_add("/dev/disk/guestfs/b", "p", 100 * 1024 * 2, -64)

# Check the partitions exist using both the disk label and raw name.
if g.blockdev_getsize64("/dev/disk/guestfs/a1") != g.blockdev_getsize64("/dev/sda1"):
    raise Exception("Sizes do not match for a1/sda1")

if g.blockdev_getsize64("/dev/disk/guestfs/b1") != g.blockdev_getsize64("/dev/sdb1"):
    raise Exception("Sizes do not match for b1/sdb1")

if g.blockdev_getsize64("/dev/disk/guestfs/b2") != g.blockdev_getsize64("/dev/sdb2"):
    raise Exception("Sizes do not match for b2/sdb2")

# Check list_disk_labels
labels = g.list_disk_labels()

if "a" not in labels:
    raise Exception("Label 'a' not found")
if labels["a"] != "/dev/sda":
    raise Exception("Label 'a' does not map to /dev/sda")

if "b" not in labels:
    raise Exception("Label 'b' not found")
if labels["b"] != "/dev/sdb":
    raise Exception("Label 'b' does not map to /dev/sdb")

if "a1" not in labels:
    raise Exception("Label 'a1' not found")
if labels["a1"] != "/dev/sda1":
    raise Exception("Label 'a1' does not map to /dev/sda1")

if "b1" not in labels:
    raise Exception("Label 'b1' not found")
if labels["b1"] != "/dev/sdb1":
    raise Exception("Label 'b1' does not map to /dev/sdb1")

if "b2" not in labels:
    raise Exception("Label 'b2' not found")
if labels["b2"] != "/dev/sdb2":
    raise Exception("Label 'b2' does not map to /dev/sdb2")

sys.exit(0)
