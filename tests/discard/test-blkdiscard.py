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
# Test that blkdiscard works.

import os
import sys
import atexit
import guestfs

prog = os.path.basename(sys.argv[0])

# Force English error messages so test output is stable and greppable.
os.environ["LANG"] = "C"

# Skip the test if the user requested it explicitly.
if os.environ.get("SKIP_TEST_BLKDISCARD_PY"):
    print(f"{prog}: skipped test because environment variable is set")
    sys.exit(77)

# Create a new libguestfs handle.
g = guestfs.GuestFS()

# Discard is only supported when using qemu-based backends.
backend = g.get_backend()
if backend not in ("direct", "libvirt") and not backend.startswith("libvirt:"):
    print(f"{prog}: skipped test because discard is only supported when using qemu")
    sys.exit(77)

# You can set this to "raw" or "qcow2", mirroring the Perl test.
FORMAT = "raw"

# Disk size: 5 MiB, same as the Perl version.
SIZE = 5 * 1024 * 1024

# Decide the on-disk image name and creation options based on the format.
if FORMAT == "raw":
    disk = "test-blkdiscard.img"
    create_opts = {"preallocation": "sparse"}
elif FORMAT == "qcow2":
    disk = "test-blkdiscard.qcow2"
    create_opts = {"preallocation": "off", "compat": "1.1"}
else:
    raise RuntimeError(f"{prog}: invalid disk format: {FORMAT}")

# Ensure the test image is cleaned up on exit, regardless of success/failure.
def cleanup() -> None:
    try:
        if os.path.exists(disk):
            os.unlink(disk)
    except OSError:
        # Ignore cleanup errors – they should not affect the test result.
        pass

atexit.register(cleanup)

# Create a disk and add it with discard enabled.
# This is allowed to fail, e.g. because qemu is too old; in that case
# libguestfs must tell us that it failed (since we're using 'enable',
# not 'besteffort').
g.disk_create(disk, FORMAT, SIZE, **create_opts)

try:
    g.add_drive(disk, format=FORMAT, readonly=False, discard="enable")
    g.launch()
except RuntimeError as e:
    msg = str(e)
    if "discard cannot be enabled on this drive" in msg:
        # This is OK.  Libguestfs says it's not possible to enable
        # discard on this drive (e.g. because qemu is too old).
        # Print the reason and skip the test.
        print(f"{prog}: skipped test: {msg}")
        sys.exit(77)
    # Anything else is unexpected and should fail the test.
    raise

# Check if blkdiscard support is available in the appliance.
if not g.feature_available(["blkdiscard"]):
    print(f"{prog}: skipped test because BLKDISCARD is not available")
    sys.exit(77)

# At this point we've got a disk which claims to support discard.
# Let's test that theory.

# st_blocks is the number of 512-byte blocks allocated for the file.
orig_size = os.stat(disk).st_blocks
print(f"original size:\t{orig_size} (blocks)")

# Fill the block device with non-zero data so that the file becomes fully
# allocated on the host filesystem.
remaining = SIZE
offset = 0
chunk_size = 1024 * 1024  # Write in 1 MiB chunks, like the Perl test.

while remaining > 0:
    # Amount to write in this iteration.
    this_chunk = min(chunk_size, remaining)
    # Use '*' bytes to ensure we write non-zero data.
    data = b"*" * this_chunk
    # Write directly to the guest block device.
    g.pwrite_device("/dev/sda", data, offset)
    offset += this_chunk
    remaining -= this_chunk

# Ensure all writes are flushed.
g.sync()

full_size = os.stat(disk).st_blocks
print(f"full size:\t{full_size} (blocks)")

if full_size <= orig_size:
    raise RuntimeError(f"{prog}: surprising result: full size <= original size")

# Discard the data on the device.
# The Perl test calls $g->blkdiscard("/dev/sda"); which discards the device.
# The Python binding has the same interface: single argument for the device.
g.blkdiscard("/dev/sda")

# Cleanly shut down the appliance.
g.shutdown()
g.close()

trimmed_size = os.stat(disk).st_blocks
print(f"trimmed size:\t{trimmed_size} (blocks)")

# Require that blkdiscard actually freed a significant number of blocks.
freed = full_size - trimmed_size
if freed < 1000:
    raise RuntimeError(
        f"{prog}: looks like the blkdiscard operation did not work "
        f"(freed only {freed} blocks)"
    )
