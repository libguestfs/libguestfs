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

# Test long directories and protocol limits.

import os
import sys
import guestfs

prog = os.path.basename(sys.argv[0])

# Slow test gating.
if "SLOW" not in os.environ:
    print(f"{prog}: use 'make check-slow' to run this test")
    sys.exit(77)

if os.environ.get("SKIP_TEST_BIG_DIRS_PY"):
    print(f"{prog}: test skipped because SKIP_TEST_BIG_DIRS_PY is set")
    sys.exit(77)

# Create a 2 GB test file (sparse).
nr_files = 1_000_000
image_size = 2 * 1024 * 1024 * 1024

g = guestfs.GuestFS(python_return_dict=True)
g.add_drive_scratch(image_size)

g.launch()

g.part_disk("/dev/sda", "mbr")
g.mkfs("ext4", "/dev/sda1")
g.mke2fs("/dev/sda1", fstype="ext4", bytesperinode=2048)
g.mount("/dev/sda1", "/")

df = g.statvfs("/")
if df["favail"] <= nr_files:
    raise RuntimeError(f"{prog}: internal error: not enough inodes on filesystem")

# Create a very large directory. The aim is that the number of files
# * length of each filename should be longer than a protocol message
# (currently 4 MB).
g.mkdir("/dir")
g.fill_dir("/dir", nr_files)

# Listing the directory should be OK.
filenames = g.ls("/dir")

# Check the names (they should be sorted).
if len(filenames) != nr_files:
    raise RuntimeError("incorrect number of filenames returned by g.ls")

for i, name in enumerate(filenames):
    if name != f"{i:08d}":
        raise RuntimeError(f"unexpected filename at index {i}: {name}")

# Check that lstatlist, lxattrlist and readlinklist return the expected number.
a = g.lstatlist("/dir", filenames)
if len(a) != nr_files:
    raise RuntimeError("lstatlist returned wrong number of entries")

a = g.lxattrlist("/dir", filenames)
if len(a) != nr_files:
    raise RuntimeError("lxattrlist returned wrong number of entries")

a = g.readlinklist("/dir", filenames)
if len(a) != nr_files:
    raise RuntimeError("readlinklist returned wrong number of entries")

g.shutdown()
g.close()
