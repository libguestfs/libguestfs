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
#
# Test that fstrim works.

import os
import sys
import atexit
import guestfs

prog = os.path.basename(sys.argv[0])

# Ensure errors appear in English for deterministic output.
os.environ["LANG"] = "C"

# Allow skipping via environment variable (consistent with Perl test).
if os.environ.get("SKIP_TEST_FSTRIM_PY"):
    print(f"{prog}: skipped test because environment variable is set")
    sys.exit(77)

# Create guestfs handle.
g = guestfs.GuestFS()

# Discard support requires QEMU backends only.
backend = g.get_backend()
if backend not in ("direct", "libvirt") and not backend.startswith("libvirt:"):
    print(f"{prog}: skipped test because discard is only supported when using qemu")
    sys.exit(77)

# Disk format: raw or qcow2 (same default as Perl version).
FORMAT = "raw"

# Must be at least 32 MB for ext4 → use 64 MB, identical to the Perl test.
SIZE = 64 * 1024 * 1024

# Disk filename + options.
if FORMAT == "raw":
    disk = "test-fstrim.img"
    create_opts = {"preallocation": "sparse"}
elif FORMAT == "qcow2":
    disk = "test-fstrim.qcow2"
    create_opts = {"preallocation": "off", "compat": "1.1"}
else:
    raise RuntimeError(f"{prog}: invalid disk format: {FORMAT}")

# Remove disk on exit.
def cleanup():
    try:
        if os.path.exists(disk):
            os.unlink(disk)
    except OSError:
        pass

atexit.register(cleanup)

# Create disk.
g.disk_create(disk, FORMAT, SIZE, **create_opts)

# Try enabling discard explicitly; failure may be legitimate.
try:
    g.add_drive(disk, format=FORMAT, readonly=False, discard="enable")
    g.launch()
except RuntimeError as e:
    msg = str(e)
    if "discard cannot be enabled on this drive" in msg:
        print(f"{prog}: skipped test: {msg}")
        sys.exit(77)
    raise  # unexpected error

# Check fstrim availability in appliance.
if not g.feature_available(["fstrim"]):
    print(f"{prog}: skipped test because fstrim is not available")
    sys.exit(77)

# Measure initial sparse size.
orig_size = os.stat(disk).st_blocks
print(f"original size:\t{orig_size} (blocks)")

# Make ext4 filesystem.
g.mkfs("ext4", "/dev/sda")

# Mount with *nodiscard* so removing the file will NOT automatically trigger TRIM.
# We want to test the *explicit* fstrim operation.
g.mount_options("nodiscard", "/dev/sda", "/")

# Fill large file with lots of small data (same pattern as Perl: fill 33 10000000 /data).
g.fill(33, 10_000_000, "/data")
g.sync()

full_size = os.stat(disk).st_blocks
print(f"full size:\t{full_size} (blocks)")

if full_size <= orig_size:
    raise RuntimeError(f"{prog}: surprising result: full size <= original size")

# Remove file but trimming will NOT occur (nodiscard prevents it).
g.rm("/data")

# Now explicitly run fstrim on the mountpoint.
g.fstrim("/")

# Shutdown appliance cleanly.
g.shutdown()
g.close()

trimmed_size = os.stat(disk).st_blocks
print(f"trimmed size:\t{trimmed_size} (blocks)")

# Ensure meaningful trimming occurred.
if full_size - trimmed_size < 1000:
    raise RuntimeError(f"{prog}: looks like the fstrim operation did not work")
