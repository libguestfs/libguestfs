#!/usr/bin/env python3
# libguestfs
# Copyright (C) 2010-2025 Red Hat Inc.
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
# With: CLI args, type hints, robust error handling, pathlib, structured logging,
# modular design, auto-cleanup, configurable image name/size/version, and
# prefilled Windows version metadata written into the image.

"""
make-windows-img.py

High-level overview
-------------------

This script creates a *phony* Windows disk image used by the libguestfs
test suite. It is not a real Windows installation, but it looks “real
enough” for the libguestfs inspection heuristics to recognize it as a
Windows guest and for tests to exercise Windows-related inspection logic.

The image contains:

* An MBR partition table with two NTFS partitions.
* A phony “system” partition and “boot” partition.
* Minimal Windows registry hives and binaries placed under
  /Windows/System32/Config and /Windows/System32.
* A fixed disk ID written into the MBR at offset 0x1b8.
* A small metadata file recording the intended Windows version mapping
  (major, minor, build, server/client, ID) at
  /Windows/GuestfsVersionInfo.txt.

Windows version branding
------------------------

libguestfs inspection maps Windows installations to short IDs such as:

    winxp, win2k3, winvista, win7, win8, win8.1,
    win10, win11, win2k16, win2k19, win2k22, win2k25

based on product name, variant, build ID and (major, minor) version.

This script does **not** modify registry hives itself. Instead:

* By default (no version specified) it uses generic hives:

    SRCDIR/windows-software
    SRCDIR/windows-system

  and writes a metadata file with `windows_id=generic`.

* If you pass `--windows-version-id=<ID>`, the script:

    - expects version-specific hive files:
          SRCDIR/windows-software-<ID>
          SRCDIR/windows-system-<ID>
    - looks up pre-filled metadata for that ID (major, minor, build,
      server/client role, human-readable name) and writes it to
      /Windows/GuestfsVersionInfo.txt inside the image.

This lets tests or developers easily verify which Windows profile the
image is supposed to represent without re-running inspection.

How to run it
-------------

The script uses CLI arguments only (no environment-variable fallback).

Basic usage (default generic image, keeps original behaviour):

.. code-block:: console

    ./make-windows-img.py /path/to/test-data/phony-guests

This will create a 512 MiB `windows.img` in the current directory.

Custom output directory and name:

.. code-block:: console

    ./make-windows-img.py ./test-data/phony-guests \
        --output-dir /tmp/images --name win-phony

Specify a Windows version profile (e.g. win10, win11, win2k22):

.. code-block:: console

    ./make-windows-img.py ./test-data/phony-guests \
        --windows-version-id win10

This will look for:

    ./test-data/phony-guests/windows-software-win10
    ./test-data/phony-guests/windows-system-win10

and write metadata like:

    windows_id=win10
    major=10
    minor=0
    is_server=0
    build_id=19045
    product_name=Windows 10 (Phony)
    product_variant=Client

at /Windows/GuestfsVersionInfo.txt.

Adjust image size (in MiB):

.. code-block:: console

    ./make-windows-img.py ./test-data/phony-guests --size-mib 1024

Feature detection
-----------------

If the currently compiled libguestfs does not have NTFS support
(ntfs-3g/ntfsprogs), we cannot create a Windows phony image. In that case:

* A warning is printed.
* An empty placeholder image is created at the requested path.
* The script exits successfully (status 0), so tests can treat this as
  “not supported” instead of a hard failure.

Important invariants
--------------------

* The partition layout (two primary partitions with a specific gap) and
  disk ID are part of the “test contract” and should not be changed
  without reviewing all tests that rely on them.
* Paths under the phony Windows tree (/Windows/System32/Config,
  /Windows/System32/cmd.exe, /Program Files, /autoexec.bat) are used by
  inspection tests.
* This script assumes the following base files exist under `SRCDIR`:

    * `windows-software[{-ID}]` → registry SOFTWARE hive
    * `windows-system[{-ID}]`   → registry SYSTEM hive
    * `../binaries/bin-win32.exe` → a small Win32 executable

  where `{ID}` is an optional version ID like `winxp` or `win10`.
"""

from __future__ import annotations

import argparse
import atexit
import os
import sys
from pathlib import Path
from typing import NoReturn

import guestfs

# Configuration constants
# -----------------------
# Default size of the Windows phony image (MiB).
DEFAULT_SIZE_MIB = 512

# Partition layout (in sectors, 512 bytes each).
# For historical consistency this mirrors the old shell script:
#
#   /dev/sda1: starts at sector 64, ends at 524287
#   /dev/sda2: starts at 524288, ends at -64 (libguestfs “until last-64”)
#
LEADING_SECTORS = 64
TRAILING_SECTORS = 64

# Windows version metadata
# ------------------------
# Representative (major, minor, build, server/client, names) for IDs that
# libguestfs inspection code can return. These are *not* exhaustive, but
# good enough for test metadata baked into the image.
WINDOWS_VERSION_METADATA: dict[str, dict[str, object]] = {
    "winxp": {
        "major": 5,
        "minor": 1,
        "is_server": False,
        "build_id": 2600,
        "product_name": "Windows XP (Phony)",
        "product_variant": "Client",
    },
    "win2k3": {
        "major": 5,
        "minor": 2,
        "is_server": True,
        "build_id": 3790,
        "product_name": "Windows Server 2003 (Phony)",
        "product_variant": "Server",
    },
    "winvista": {
        "major": 6,
        "minor": 0,
        "is_server": False,
        "build_id": 6002,
        "product_name": "Windows Vista (Phony)",
        "product_variant": "Client",
    },
    "win2k8": {
        "major": 6,
        "minor": 0,
        "is_server": True,
        "build_id": 6002,
        "product_name": "Windows Server 2008 (Phony)",
        "product_variant": "Server",
    },
    "win7": {
        "major": 6,
        "minor": 1,
        "is_server": False,
        "build_id": 7601,
        "product_name": "Windows 7 (Phony)",
        "product_variant": "Client",
    },
    "win2k8r2": {
        "major": 6,
        "minor": 1,
        "is_server": True,
        "build_id": 7601,
        "product_name": "Windows Server 2008 R2 (Phony)",
        "product_variant": "Server",
    },
    "win8": {
        "major": 6,
        "minor": 2,
        "is_server": False,
        "build_id": 9200,
        "product_name": "Windows 8 (Phony)",
        "product_variant": "Client",
    },
    "win2k12": {
        "major": 6,
        "minor": 2,
        "is_server": True,
        "build_id": 9200,
        "product_name": "Windows Server 2012 (Phony)",
        "product_variant": "Server",
    },
    "win8.1": {
        "major": 6,
        "minor": 3,
        "is_server": False,
        "build_id": 9600,
        "product_name": "Windows 8.1 (Phony)",
        "product_variant": "Client",
    },
    "win2k12r2": {
        "major": 6,
        "minor": 3,
        "is_server": True,
        "build_id": 9600,
        "product_name": "Windows Server 2012 R2 (Phony)",
        "product_variant": "Server",
    },
    "win10": {
        "major": 10,
        "minor": 0,
        "is_server": False,
        "build_id": 19045,  # representative Windows 10 22H2
        "product_name": "Windows 10 (Phony)",
        "product_variant": "Client",
    },
    "win11": {
        "major": 10,
        "minor": 0,
        "is_server": False,
        "build_id": 22621,  # representative Windows 11 22H2
        "product_name": "Windows 11 (Phony)",
        "product_variant": "Client",
    },
    "win2k16": {
        "major": 10,
        "minor": 0,
        "is_server": True,
        "build_id": 14393,
        "product_name": "Windows Server 2016 (Phony)",
        "product_variant": "Server",
    },
    "win2k19": {
        "major": 10,
        "minor": 0,
        "is_server": True,
        "build_id": 17763,
        "product_name": "Windows Server 2019 (Phony)",
        "product_variant": "Server",
    },
    "win2k22": {
        "major": 10,
        "minor": 0,
        "is_server": True,
        "build_id": 20348,
        "product_name": "Windows Server 2022 (Phony)",
        "product_variant": "Server",
    },
    "win2k25": {
        # future / hypothetical mapping (used by handle_windows)
        "major": 10,
        "minor": 0,
        "is_server": True,
        "build_id": 26000,
        "product_name": "Windows Server 2025 (Phony)",
        "product_variant": "Server",
    },
    # Fallback "generic" profile, used when no explicit version ID is given.
    "generic": {
        "major": 0,
        "minor": 0,
        "is_server": False,
        "build_id": 0,
        "product_name": "Generic Windows (Phony)",
        "product_variant": "Unknown",
    },
}


def known_windows_ids() -> set[str]:
    """
    Return the set of known Windows version IDs that we have metadata for.
    """
    return set(WINDOWS_VERSION_METADATA.keys())


def info(msg: str) -> None:
    """Print an informational message to stdout."""
    print(f"ℹ  {msg}")


def success(msg: str) -> None:
    """Print a success message to stdout."""
    print(f"✓  {msg}")


def warn(msg: str) -> None:
    """Print a warning message to stdout."""
    print(f"⚠  {msg}")


def error(msg: str) -> NoReturn:
    """Print an error message to stderr and exit non-zero."""
    print(f"✗  {msg}", file=sys.stderr)
    sys.exit(1)


class WindowsImageCreator:
    """
    Create a phony Windows image for libguestfs tests.

    Parameters
    ----------
    srcdir:
        Directory containing the Windows test data files:
          - windows-software[-ID]
          - windows-system[-ID]
          - ../binaries/bin-win32.exe

    output_dir:
        Directory where the resulting image will be written.

    name:
        Basename (without extension) of the output image. The final file
        will be `<name>.img`.

    size_mib:
        Size of the disk image in MiB. Historically 512 MiB, but can be
        adjusted via CLI for experimentation.

    windows_id:
        Optional short Windows version ID, e.g. "winxp", "win7", "win10",
        "win11", "win2k22". When set, the script will look for
        `windows-software-<ID>` and `windows-system-<ID>` in srcdir,
        and will bake prefilled metadata for this ID into
        /Windows/GuestfsVersionInfo.txt.
    """

    def __init__(
        self,
        srcdir: Path,
        output_dir: Path,
        name: str,
        size_mib: int,
        windows_id: str | None,
    ) -> None:
        self.srcdir = srcdir
        self.output_dir = output_dir
        self.name = name
        self.size_mib = size_mib
        self.windows_id = windows_id

        # Temporary and final image paths
        self.temp_image = Path(f"{self.name}.img-t")
        self.final_image = self.output_dir / f"{self.name}.img"

        # Main guestfs handle
        self.g = guestfs.GuestFS(python_return_dict=True)

        # Ensure cleanup (shutdown/close + no stray temp files)
        atexit.register(self._cleanup)

    def _cleanup(self) -> None:
        """Best-effort cleanup of guestfs handle and temporary image."""
        try:
            self.g.shutdown()
            self.g.close()
        except Exception:
            pass

        try:
            if self.temp_image.exists():
                self.temp_image.unlink()
        except Exception:
            pass

    @staticmethod
    def _check_ntfs_support() -> bool:
        """
        Check whether this libguestfs build has NTFS support.

        We use a short-lived handle to avoid polluting the main one.
        Equivalent in spirit to:

            guestfish -a /dev/null run : available "ntfs3g ntfsprogs"
        """
        g2 = guestfs.GuestFS(python_return_dict=True)
        try:
            g2.add_drive("/dev/null")
            g2.launch()
            # This returns True only if the requested features are available.
            return g2.feature_available(["ntfs3g", "ntfsprogs"])
        finally:
            try:
                g2.shutdown()
                g2.close()
            except Exception:
                pass

    def _create_placeholder(self) -> None:
        """
        Create an empty placeholder image when NTFS support is not available.

        This preserves the behaviour of the original shell script (touch
        windows.img) but honours the configured name and output directory.
        """
        warn("cannot create full Windows image because NTFS support is missing")
        warn("creating an empty placeholder image instead")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.final_image.touch()
        success(f"Placeholder image created → {self.final_image}")

    def _create_disk_and_partitions(self) -> None:
        """
        Create the sparse disk image, MBR, and NTFS partitions.

        Layout:

            /dev/sda1: phony bootloader/system partition (NTFS)
            /dev/sda2: phony root filesystem (NTFS)
        """
        size_bytes = self.size_mib * 1024 * 1024
        info(f"Creating sparse disk image {self.temp_image} ({self.size_mib} MiB)")
        self.g.disk_create(str(self.temp_image), "raw", size_bytes)
        self.g.add_drive(str(self.temp_image), format="raw")
        self.g.launch()

        info("Initializing MBR partition table")
        self.g.part_init("/dev/sda", "mbr")

        # Partition 1: /dev/sda1
        self.g.part_add("/dev/sda", "p", LEADING_SECTORS, 524287)
        # Partition 2: /dev/sda2, from 524288 to -64 (leave trailing sectors)
        self.g.part_add("/dev/sda", "p", 524288, -TRAILING_SECTORS)

        # Disk ID at offset 0x1b8: "1234" (ASCII)
        info("Writing disk ID at MBR offset 0x1b8")
        self.g.pwrite_device("/dev/sda", b"1234", 0x1B8)

        info("Creating NTFS filesystems")
        self.g.mkfs("ntfs", "/dev/sda1")
        self.g.mkfs("ntfs", "/dev/sda2")

    def _select_hive_files(self) -> tuple[Path, Path, str]:
        """
        Select SOFTWARE and SYSTEM hive files and the effective Windows ID.

        If self.windows_id is None:
            - use windows-software and windows-system.
            - effective_id = "generic"

        If self.windows_id is set to e.g. "win10":
            - prefer windows-software-win10 and windows-system-win10.
            - effective_id = that ID
        """
        if self.windows_id:
            info(f"Target Windows version ID: {self.windows_id}")
            software = self.srcdir / f"windows-software-{self.windows_id}"
            system = self.srcdir / f"windows-system-{self.windows_id}"
            return software, system, self.windows_id

        # Default legacy behaviour: generic hives.
        software = self.srcdir / "windows-software"
        system = self.srcdir / "windows-system"
        return software, system, "generic"

    def _write_version_metadata_file(self, effective_id: str) -> None:
        """
        Write /Windows/GuestfsVersionInfo.txt with prefilled version metadata.

        This is purely test/debug metadata and does not affect inspection
        directly (the latter still reads the registry). It records:

            windows_id
            major
            minor
            is_server
            build_id
            product_name
            product_variant
        """
        meta = WINDOWS_VERSION_METADATA.get(effective_id)
        if not meta:
            # Fallback to generic metadata if we don't have a record.
            warn(f"No metadata for Windows ID '{effective_id}', using 'generic'")
            meta = WINDOWS_VERSION_METADATA["generic"]
            meta = dict(meta)  # copy so we can override ID
        else:
            meta = dict(meta)

        meta.setdefault("major", 0)
        meta.setdefault("minor", 0)
        meta.setdefault("is_server", False)
        meta.setdefault("build_id", 0)
        meta.setdefault("product_name", "Unknown (Phony)")
        meta.setdefault("product_variant", "Unknown")
        meta["windows_id"] = effective_id

        lines = [
            f"windows_id={meta['windows_id']}",
            f"major={meta['major']}",
            f"minor={meta['minor']}",
            f"is_server={int(bool(meta['is_server']))}",
            f"build_id={meta['build_id']}",
            f"product_name={meta['product_name']}",
            f"product_variant={meta['product_variant']}",
            "",
        ]
        content = "\n".join(lines)
        info("Writing Windows version metadata to /Windows/GuestfsVersionInfo.txt")
        self.g.write("/Windows/GuestfsVersionInfo.txt", content)

    def _populate_filesystems(self) -> None:
        """
        Populate the phony Windows filesystem tree.

        We mount /dev/sda2 as / and create just enough structure to fool
        the inspection API, plus a metadata file for test/debug use:

          - /Windows/System32/Config/{SOFTWARE,SYSTEM}
          - /Windows/System32/cmd.exe
          - /Windows/GuestfsVersionInfo.txt (version metadata)
          - /Program Files
          - /autoexec.bat
        """
        info("Mounting phony Windows root filesystem")
        self.g.mount("/dev/sda2", "/")

        # Directory structure
        for d in [
            "/Windows",
            "/Windows/System32",
            "/Windows/System32/Config",
            "/Windows/System32/Drivers",
        ]:
            self.g.mkdir_p(d)

        software, system, effective_id = self._select_hive_files()
        win32_bin = self.srcdir / "../binaries/bin-win32.exe"

        if not software.is_file():
            error(f"Missing SOFTWARE hive: {software}")
        if not system.is_file():
            error(f"Missing SYSTEM hive: {system}")
        if not win32_bin.is_file():
            error(f"Missing Win32 test binary: {win32_bin}")

        info("Uploading registry hives")
        self.g.upload(str(software), "/Windows/System32/Config/SOFTWARE")
        self.g.upload(str(system), "/Windows/System32/Config/SYSTEM")

        info("Uploading cmd.exe test binary")
        self.g.upload(str(win32_bin), "/Windows/System32/cmd.exe")

        info("Creating additional phony Windows structures")
        self.g.mkdir("/Program Files")
        self.g.touch("/autoexec.bat")

        # Write version metadata file inside the Windows tree.
        self._write_version_metadata_file(effective_id)

        self.g.umount_all()
        success("Phony Windows filesystem populated")

    def run(self) -> None:
        """
        Main entry point: check features, create disk, populate, finalize.
        """
        if not self._check_ntfs_support():
            self._create_placeholder()
            return

        # Create image and populate it.
        self._create_disk_and_partitions()
        self._populate_filesystems()

        # Ensure output dir exists and rename temporary image into place.
        self.output_dir.mkdir(parents=True, exist_ok=True)
        info(f"Moving temporary image to final location: {self.final_image}")
        os.rename(self.temp_image, self.final_image)
        success(f"Windows phony image ready → {self.final_image}")


def main() -> None:
    """
    Parse CLI arguments, validate inputs, and drive WindowsImageCreator.
    """
    parser = argparse.ArgumentParser(
        description="Create phony Windows guest images for libguestfs tests",
    )

    parser.add_argument(
        "srcdir",
        type=Path,
        help="Directory with Windows test data (e.g. test-data/phony-guests)",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("."),
        help="Directory in which to place the final image (default: CWD)",
    )
    parser.add_argument(
        "-n",
        "--name",
        default="windows",
        help="Base name of the image file (default: windows → windows.img)",
    )
    parser.add_argument(
        "--size-mib",
        type=int,
        default=DEFAULT_SIZE_MIB,
        help=f"Disk size in MiB (default: {DEFAULT_SIZE_MIB})",
    )
    parser.add_argument(
        "-w",
        "--windows-version-id",
        dest="windows_id",
        help=(
            "Short Windows version ID used by inspection (e.g. "
            "winxp, win2k3, winvista, win7, win8, win8.1, "
            "win10, win11, win2k16, win2k19, win2k22, win2k25). "
            "When set, the script looks for windows-software-<ID> "
            "and windows-system-<ID> in SRCDIR and writes matching "
            "metadata to /Windows/GuestfsVersionInfo.txt."
        ),
    )

    args = parser.parse_args()

    if not args.srcdir.is_dir():
        error(f"SRCDIR not a directory: {args.srcdir}")

    if args.size_mib <= 0:
        error(f"Invalid size: {args.size_mib} (must be > 0 MiB)")

    if args.windows_id and args.windows_id not in known_windows_ids():
        # Soft warning only: users may add future IDs before updating this list.
        warn(
            f"Windows version ID '{args.windows_id}' is not in the known set "
            f"{sorted(known_windows_ids())}; proceeding anyway and using "
            "generic metadata if no explicit record exists."
        )

    creator = WindowsImageCreator(
        srcdir=args.srcdir.resolve(),
        output_dir=args.output_dir.resolve(),
        name=args.name,
        size_mib=args.size_mib,
        windows_id=args.windows_id,
    )
    creator.run()

    print("\nAll done! Phony Windows image is ready for libguestfs testing")


if __name__ == "__main__":
    main()
