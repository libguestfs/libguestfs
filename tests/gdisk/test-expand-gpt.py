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

"""
Test: part-expand-gpt functionality (expands GPT backup table when disk grows)

This test verifies that libguestfs correctly expands the GPT backup partition
table when the underlying disk is resized larger using qemu-img resize.

It also checks:
- That it works (GPT disk)
- That it fails gracefully on MBR disks
- That it still works after shrinking and growing again
"""

import os
import sys
import subprocess
from pathlib import Path

import guestfs

# Skip conditions (same as original test)
if os.environ.get("SKIP_TEST_EXPAND_GPT_PY"):
    print(f"{sys.argv[0]}: test skipped because SKIP_TEST_EXPAND_GPT_PY is set")
    sys.exit(77)

if subprocess.run(["sgdisk", "--help"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
    print(f"{sys.argv[0]}: test skipped because sgdisk program not found")
    sys.exit(77)

# Test implementation
def run_tests():
    img_dir = Path("gdisk")
    img_dir.mkdir(exist_ok=True)

    gpt_img = img_dir / "disk_gpt.img"
    mbr_img = img_dir / "disk_mbr.img"

    # Create two 50M disks: one GPT, one MBR
    g = guestfs.GuestFS()
    for pt, img in [("gpt", gpt_img), ("mbr", mbr_img)]:
        g.disk_create(str(img), "qcow2", 50 * 1024 * 1024)
        g.add_drive(str(img), format="qcow2")
    g.launch()

    g.part_disk("/dev/sda", "gpt")
    g.part_disk("/dev/sdb", "mbr")
    g.close()

    # Resize GPT disk to 100M
    subprocess.check_call(["qemu-img", "resize", str(gpt_img), "100M"], stdout=subprocess.DEVNULL)

    # Reopen and expand GPT
    g = guestfs.GuestFS()
    g.add_drive(str(gpt_img), format="qcow2")
    g.add_drive(str(mbr_img), format="qcow2")
    g.launch()

    # This should succeed
    g.part_expand_gpt("/dev/sda")

    # Verify using sgdisk -p that last usable sector is close to end
    output = g.debug("sh", ["sgdisk", "-p", "/dev/sda"])
    if not output.strip():
        raise RuntimeError("sgdisk -p returned empty output")

    # Extract last usable sector
    import re
    m = re.search(r"last usable sector is (\d+)", output)
    if not m:
        raise RuntimeError(f"Could not parse sgdisk output: {output}")
    last_usable = int(m.group(1))

    total_sectors = 100 * 1024 * 1024 // 512
    unused_sectors = total_sectors - last_usable - 1  # -1 for backup GPT itself
    if unused_sectors > 34:
        raise RuntimeError(f"Too many unused sectors at end: {unused_sectors} (expected ≤34)")

    # Negative test: should fail on MBR disk
    try:
        g.part_expand_gpt("/dev/sdb")
        raise RuntimeError("part_expand_gpt unexpectedly succeeded on MBR disk")
    except RuntimeError as e:
        if "Non-GPT disk" not in str(e):
            raise RuntimeError(f"Unexpected error message: {e}")

    g.close()

    # Now test shrink → grow cycle
    subprocess.check_call(["qemu-img", "resize", "--shrink", str(gpt_img), "50M"], stdout=subprocess.DEVNULL)
    subprocess.check_call(["qemu-img", "resize", str(gpt_img), "100M"], stdout=subprocess.DEVNULL)

    g = guestfs.GuestFS()
    g.add_drive(str(gpt_img), format="qcow2")
    g.launch()

    g.part_expand_gpt("/dev/sda")

    output = g.debug("sh", ["sgdisk", "-p", "/dev/sda"])
    m = re.search(r"last usable sector is (\d+)", output)
    if not m:
        raise RuntimeError("Failed to parse sgdisk output after shrink+grow")
    last_usable = int(m.group(1))

    total_sectors = 100 * 1024 * 1024 // 512
    unused_sectors = total_sectors - last_usable - 1
    if unused_sectors > 34:
        raise RuntimeError(f"After shrink+grow: too many unused sectors: {unused_sectors}")

    g.close()
    print("All part-expand-gpt tests passed")

# Run and cleanup
try:
    run_tests()
except Exception as e:
    print(f"Test failed: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    # Clean up test images
    for img in Path("gdisk").glob("disk_*.img"):
        try:
            img.unlink()
        except FileNotFoundError:
            pass
    try:
        Path("gdisk").rmdir()
    except OSError:
        pass  # not empty or doesn't exist

sys.exit(0)
