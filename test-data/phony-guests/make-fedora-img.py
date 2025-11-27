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
# With: CLI args, type hints, robust error handling,
# pathlib, modular structure, verbose control, auto-cleanup.

"""
make-fedora-img.py

High-level overview
-------------------

This script creates *phony* Fedora disk images used by the libguestfs test
suite. A “phony” image is not a full OS installation, but it looks “real
enough” for the libguestfs inspection code to detect it as a Fedora guest and
for various tests to exercise inspection and filesystem APIs.

The goal of this script is to deterministically build small, self-contained
images with a very specific layout and content:

* Partitioning and gaps are historically preserved (including a 32 KiB gap
  between partitions) because tests depend on these exact offsets.
* Filesystems, labels, UUIDs, paths and test files are fixed and must not
  change without updating the corresponding tests.
* Several different layouts are supported so tests can exercise different
  stacking combinations (plain partitions, MD RAID, Btrfs, LVM+LUKS, etc.).
* The Fedora version string embedded in /etc/*release and /etc/motd can be
  chosen at runtime (e.g. 43, 42, rawhide) while keeping all structural
  details identical.

Where this script is used
-------------------------

The generated images are consumed by multiple libguestfs test directories such
as:

* tests/guests/
* tests/inspect/
* tests/btrfs/
* tests/luks/
* tests/mdadm/
* and any other tests that need a “known good” Fedora guest layout

Typically it is called from `make check` (via the Makefile in
`test-data/phony-guests/`) and not directly by users. However it can also be
run manually when developing or debugging the tests.

How to run it
-------------

The script uses CLI arguments.

Basic usage:

.. code-block:: console

    ./make-fedora-img.py partitions     /path/to/test-data/phony-guests
    ./make-fedora-img.py partitions-md /path/to/test-data/phony-guests
    ./make-fedora-img.py btrfs         /path/to/test-data/phony-guests
    ./make-fedora-img.py lvm-on-luks   /path/to/test-data/phony-guests
    ./make-fedora-img.py luks-on-lvm   /path/to/test-data/phony-guests

We can optionally specify an alternate output directory:

.. code-block:: console

    ./make-fedora-img.py partitions /path/to/test-data/phony-guests \
        --output-dir /tmp/libguestfs-images

We can also choose which Fedora version string to embed:

.. code-block:: console

    # Fedora 43
    ./make-fedora-img.py partitions ./test-data/phony-guests -r 43

    # Fedora rawhide
    ./make-fedora-img.py btrfs ./test-data/phony-guests --fedora-version rawhide

Only the contents of /etc/redhat-release, /etc/fedora-release and /etc/motd
change. Partition layout, UUIDs, filesystem labels and image filenames stay
the same for all versions.

Supported layouts
-----------------

The `layout` argument controls which type of test image is created:

* ``partitions``
    Single disk image with:

    * /dev/sda1 → /boot (ext2)
    * 32 KiB *gap* (64 sectors × 512 bytes)
    * /dev/sda2 → LVM PV → VG ``VG`` → LV ``Root`` (ROOT filesystem) +
      three extra LVs (LV1, LV2, LV3) used by tests.

* ``partitions-md``
    Two raw disk images with identical partitioning (including the gap) which
    are then assembled into MD RAID devices:

    * /dev/md0 → /boot (RAID1 of /dev/sda1 and /dev/sdb1)
    * /dev/md/rootdev → LVM PV, same LV layout as ``partitions``

    This layout exercises MD RAID handling and mdadm configuration.

* ``btrfs``
    Single disk image with:

    * /dev/sda1 → /boot (ext2)
    * 32 KiB gap
    * /dev/sda2 → Btrfs filesystem labeled ``root`` with subvolumes:
      * ``/root``   → mounted as ``/``
      * ``/home``   → mounted as ``/home``

    This layout is used for Btrfs-specific tests and inspection logic.

* ``lvm-on-luks``
    Single disk image with:

    * /dev/sda1 → /boot (ext2)
    * 32 KiB gap
    * /dev/sda2 → LUKS container (passphrase "FEDORA") → LVM PV → VG ``VG``
      with the standard LV layout.

    This exercises the “LVM on top of LUKS” stack.

* ``luks-on-lvm``
    Single disk image with:

    * /dev/sda1 → /boot (ext2)
    * 32 KiB gap
    * /dev/sda2 → LVM PV → VG ``Volume-Group``
      containing multiple logical volumes, each of which is *individually*
      LUKS-encrypted with different passphrases and properties.

    This exercises the “many LUKS on top of LVM” stack.

Important invariants
--------------------

* The partition table on ``/dev/sda`` (including the exact start/end sectors)
  must NOT be changed without auditing the tests that assume these offsets.
* UUIDs, filesystem labels, and most of the files in ``_populate_common()``
  are part of the public “test contract”. Changing them breaks tests that rely
  on those values for inspection or verification.
* Temporary files ``fedora.fstab`` and ``fedora.mdadm`` are created in the
  current working directory and removed automatically at exit.

"""

from __future__ import annotations

import argparse
import atexit
import os
import sys
from pathlib import Path
from typing import NoReturn

import guestfs

# Configuration constants (MUST match historical Fedora layout!)
# -----------------------------------------------------------------
# We intentionally keep these values small and historically stable.
# Many tests indirectly depend on the exact disk size and partition
# offsets. Do NOT change these numbers lightly.

# Size of each raw disk image in bytes (1 GiB).
IMAGE_SIZE = 1 * 1024**3

# Logical sector size for calculations (standard 512-byte sectors).
SECTOR_SIZE = 512

# Leave this many sectors at the start of the disk.
# This covers the MBR, partition table, and some padding.
LEADING_SECTORS = 64

# Leave this many sectors at the end of the disk.
TRAILING_SECTORS = 64

# Partition table — DO NOT CHANGE THESE NUMBERS
# ---------------------------------------------
# • /dev/sda1 ends at sector 524287 → exactly 256 MiB
# • 64 sectors (32 KiB) of blank space intentionally left
# • /dev/sda2 starts at sector 524288
#
# This layout matches real Fedora installs from ~2008–2014 and is
# required by inspection tests. The magic 32 KiB gap has historically
# been present on some automatically partitioned Fedora systems, so
# tests explicitly verify that we can deal with such layouts.
PARTITIONS = [
    ["p", LEADING_SECTORS, 524287],          # boot partition (256 MiB)
    ["p", 524288, -TRAILING_SECTORS],        # root partition (after 32k gap)
]


def info(msg: str) -> None:
    """
    Print an informational message to stdout.

    These messages are meant for humans running the script manually or
    reading CI logs (e.g. GitHub Actions or downstream builders).
    """
    print(f"ℹ  {msg}")


def success(msg: str) -> None:
    """
    Print a success / completion message to stdout.

    Used after successfully completing a major step such as building a
    layout or populating common content.
    """
    print(f"✓  {msg}")


def warn(msg: str) -> None:
    """
    Print a warning message to stdout.

    Warnings indicate non-fatal issues such as missing optional features
    (e.g. btrfs support) that cause the script to fall back to a simpler
    behaviour.
    """
    print(f"⚠  {msg}")


def error(msg: str) -> NoReturn:
    """
    Print an error message to stderr and exit with a non-zero status.

    This is the central error reporting mechanism used throughout the
    script. It keeps the control flow simple and ensures a readable
    message is printed for all fatal conditions (invalid arguments, bad
    SRCDIR, unknown layout, etc.).
    """
    print(f"✗  {msg}", file=sys.stderr)
    sys.exit(1)


# Main image creator class
# ========================
#
# The FedoraImageCreator encapsulates all logic for creating the
# different layouts. Each layout method is responsible for:
#
#   * Setting `self.images` (list of temporary image filenames)
#   * Setting `self.bootdev` (device path to the boot filesystem)
#   * Creating the partitioning / MD / LVM / LUKS stack
#   * Mounting the root filesystem (or relevant top-level FS) at "/"
#
# Once a layout method has run, `_populate_common()` is invoked to fill
# in the standard Fedora-like content that all layouts share.
#
# At the end, temporary images named `*.img-t` are renamed to their
# final names (without the `-t` suffix) in the requested output directory.
class FedoraImageCreator:
    """
    Create Fedora “phony” test images for libguestfs.

    Parameters
    ----------
    layout:
        Human-readable layout name (e.g. "partitions", "btrfs",
        "lvm-on-luks"). This is normalized to lowercase but otherwise
        used as-is in control flow.

    srcdir:
        Path to the directory that contains the auxiliary test data
        needed to populate the guest (RPM DB, journal, helper binaries).
        This is typically `test-data/phony-guests/`.

    output_dir:
        Directory where final `.img` files will be written. Temporary
        files are created in the current working directory with a `-t`
        suffix and then renamed to this directory.

    Attributes
    ----------
    fedora_version:
        String representing the Fedora version embedded in release files
        and motd (e.g. "14", "43", "rawhide"). Set by main() from CLI.
    """

    def __init__(self, layout: str, srcdir: Path, output_dir: Path) -> None:
        # Layout selector and paths.
        self.layout = layout.lower()
        self.srcdir = srcdir
        self.output_dir = output_dir

        # Names of raw image files created by this run.
        # Layout methods append to this list as they build images.
        self.images: list[str] = []

        # Device node used as /boot (varies by layout: /dev/sda1, /dev/md0, etc.)
        self.bootdev: str | None = None

        # Fedora version string used in /etc/*release and /etc/motd.
        # main() overwrites this with the CLI value.
        self.fedora_version: str = "14"

        # Single long-lived guestfs handle used for most layouts.
        # `python_return_dict=True` means that APIs that return hashes
        # yield Python dicts (more convenient than lists of tuples).
        self.g = guestfs.GuestFS(python_return_dict=True)

        # Register cleanup handler to ensure guestfs handle and temp
        # files are always cleaned up (even on errors).
        atexit.register(self._cleanup)

    def _cleanup(self) -> None:
        """
        Attempt to gracefully shut down the guestfs handle and remove
        temporary files created by this script.

        This function is registered with `atexit`, so it runs regardless
        of whether the script terminates normally or due to an uncaught
        exception. Any errors during cleanup are deliberately ignored.
        """
        try:
            self.g.shutdown()
            self.g.close()
        except Exception:
            # The handle might already have been closed or never
            # launched; nothing we can reasonably do at process exit.
            pass

        # Delete temporary helper files created in the current directory.
        for f in ["fedora.fstab", "fedora.mdadm"]:
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass

    # Layout: simple partitions + LVM root (preserves 32k gap)
    def _build_partitions(self) -> None:
        """
        Build a single-disk layout with MBR partitions and LVM on /dev/sda2.

        Resulting stack:

            /dev/sda1  → /boot (ext2)
            /dev/sda2  → LVM PV → VG "VG" → LV "Root" (mounted at /)
        """
        img = "fedora.img-t"
        self.images.append(img)
        self.bootdev = "/dev/sda1"

        # Create a minimal /etc/fstab for this layout. This file is later
        # uploaded into the guest in `_populate_common()`.
        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\n"
                    "LABEL=ROOT / ext2 defaults 0 0\n")

        # Create the raw disk image and attach it to the guestfs handle.
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()

        # Initialize MBR partition table on /dev/sda and add the historical
        # partition layout (including the 32 KiB gap).
        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)

        # Turn /dev/sda2 into an LVM-backed root filesystem.
        self._setup_lvm_root("/dev/sda2")

    # Layout: RAID1 across two disks (same gap on both)
    def _build_partitions_md(self) -> None:
        """
        Build two-disk RAID1 layout with MD and LVM.

        Resulting stack:

            /dev/sda{1,2}, /dev/sdb{1,2} with historical partitioning
            /dev/md0        → /boot (RAID1 over /dev/sda1, /dev/sdb1)
            /dev/md/rootdev → LVM PV → VG "VG" → LVs (same as _setup_lvm_root)
        """
        # Two temporary disk images that will participate in the RAID.
        self.images.extend(["fedora-md1.img-t", "fedora-md2.img-t"])
        self.bootdev = "/dev/md/bootdev"  # internal MD name; mapped to /dev/md0

        # Prepare /etc/fstab suitable for the MD layout. The boot device
        # is an MD device, while the root FS still uses LABEL=ROOT.
        with open("fedora.fstab", "w") as f:
            f.write("/dev/md0 /boot ext2 defaults 0 0\n"
                    "LABEL=ROOT / ext2 defaults 0 0\n")

        # Create and attach both raw disk images.
        for img in self.images:
            self.g.disk_create(img, "raw", IMAGE_SIZE)
            self.g.add_drive(img, format="raw")
        self.g.launch()

        # Initialize MBR partitioning on both disks with the same layout.
        for d in "ab":
            dev = f"/dev/sd{d}"
            self.g.part_init(dev, "mbr")
            for p in PARTITIONS:
                self.g.part_add(dev, *p)

        # Build MD RAID devices for /boot and the root PV.
        self.g.md_create("bootdev", ["/dev/sda1", "/dev/sdb1"])
        self.g.md_create("rootdev", ["/dev/sda2", "/dev/sdb2"])

        # Create an mdadm.conf that matches the constructed devices.
        with open("fedora.mdadm", "w") as f:
            f.write("MAILADDR root\nAUTO +imsm +1.x -all\n")
            for i, name in enumerate(("bootdev", "rootdev")):
                uuid = self.g.md_detail(f"/dev/md/{name}")["uuid"]
                f.write(
                    f"ARRAY /dev/md{i} level=raid1 num-devices=2 UUID={uuid}\n"
                )

        # Set up LVM on top of the RAID1 device used for the root filesystem.
        self._setup_lvm_root("/dev/md/rootdev")

    # Layout: Btrfs (still uses the same historical partition layout)
    def _build_btrfs(self) -> None:
        """
        Build a single-disk layout with Btrfs and subvolumes.

        Resulting stack:

            /dev/sda1 → /boot (ext2)
            /dev/sda2 → Btrfs (label "root") with subvolumes:
                         - root (mounted as /)
                         - home (mounted as /home)

        If btrfs support is not available in libguestfs, we produce an
        empty placeholder image and exit successfully. This keeps tests
        skippable on platforms where btrfs is not compiled in.
        """
        # Use a throwaway guestfs handle to check for btrfs support; we
        # avoid polluting the main handle with any state just for this.
        g2 = guestfs.GuestFS(python_return_dict=True)
        g2.add_drive("/dev/null")
        g2.launch()
        if not g2.feature_available(["btrfs"]):
            warn("btrfs not available → creating empty placeholder")
            Path("fedora-btrfs.img").touch()
            g2.close()
            # Exit with success; tests that need btrfs should treat this
            # as “not supported” rather than a hard failure.
            sys.exit(0)
        g2.close()

        img = "fedora-btrfs.img-t"
        self.images.append(img)
        self.bootdev = "/dev/sda1"

        # fstab for boot and btrfs subvolumes.
        with open("fedora.fstab", "w") as f:
            f.write(
                "LABEL=boot /boot ext2 defaults 0 0\n"
                "LABEL=root / btrfs subvol=root 0 0\n"
                "LABEL=root /home btrfs subvol=home 0 0\n"
            )

        # Prepare the disk and partitions.
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()

        self.g.part_init("/dev/sda", "mbr")
        # /dev/sda1 → boot
        self.g.part_add("/dev/sda", "p", 64, 524287)
        # /dev/sda2 → btrfs (after the 32 KiB gap)
        self.g.part_add("/dev/sda", "p", 524288, -64)

        # Create the btrfs filesystem and subvolumes.
        self.g.mkfs_btrfs(["/dev/sda2"], label="root")
        self.g.mount("/dev/sda2", "/")
        self.g.btrfs_subvolume_create("/root")
        self.g.btrfs_subvolume_create("/home")
        self.g.umount("/")

        # Remount the "root" subvolume as the root filesystem.
        self.g.mount("btrfsvol:/dev/sda2/root", "/")
        self.g.mkdir("/home")

        success("Btrfs layout ready")

    # Layout: LVM on LUKS (preserves gap)
    def _build_lvm_on_luks(self) -> None:
        """
        Build a layout with LVM sitting inside a LUKS container.

        Resulting stack:

            /dev/sda1 → /boot (ext2)
            /dev/sda2 → LUKS (passphrase "FEDORA") → LVM PV → VG "VG"
                          → LVs ("Root", "LV1", "LV2", "LV3")
        """
        img = "fedora-lvm-on-luks.img-t"
        self.images.append(img)
        self.bootdev = "/dev/sda1"

        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\n"
                    "LABEL=ROOT / ext2 defaults 0 0\n")

        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()

        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)

        # Encrypt the second partition, then open it as /dev/mapper/luks.
        self.g.luks_format("/dev/sda2", "FEDORA", 0)
        self.g.cryptsetup_open("/dev/sda2", "FEDORA", "luks")

        # Stack LVM on top of the LUKS mapper device.
        self._setup_lvm_root("/dev/mapper/luks")

    # Layout: LUKS on multiple LVs
    def _build_luks_on_lvm(self) -> None:
        """
        Build a layout with multiple LUKS-encrypted LVs on top of LVM.

        Resulting stack:

            /dev/sda2 → LVM PV → VG "Volume-Group" → multiple LVs
            Each LV is then LUKS-encrypted individually and formatted
            with ext2, with explicit labels / UUIDs used by tests.
        """
        img = "fedora-luks-on-lvm.img-t"
        self.images.append(img)
        self.bootdev = "/dev/sda1"

        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\n"
                    "LABEL=ROOT / ext2 defaults 0 0\n")

        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()

        # Standard partition table with the 32 KiB gap preserved.
        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)

        # Single PV/VG that hosts multiple logical volumes.
        self.g.pvcreate("/dev/sda2")
        self.g.vgcreate("Volume-Group", ["/dev/sda2"])

        # Each tuple describes a single LV→LUKS→filesystem:
        #
        #   (LV name, size MiB, LUKS password, block size,
        #    filesystem label, UUID or None)
        #
        lvs = [
            ("Root", 32, "FEDORA-Root", 4096, "ROOT",
             "01234567-0123-0123-0123-012345678902"),
            ("Logical-Volume-1", 32, "FEDORA-LV1", 4096, "LV1", None),
            ("Logical-Volume-2", 32, "FEDORA-LV2", 1024, "LV2", None),
            ("Logical-Volume-3", 64, "FEDORA-LV3", 2048, "LV3", None),
        ]

        for name, size, pw, bs, label, uuid in lvs:
            # Create LV inside the VG.
            self.g.lvcreate(name, "Volume-Group", size)
            dev = f"/dev/Volume-Group/{name}"

            # LUKS-encrypt the LV and open it.
            self.g.luks_format(dev, pw, 0)
            mapper = "root-luks" if name == "Root" else f"lv{name[-1]}-luks"
            self.g.cryptsetup_open(dev, pw, mapper)

            # Create an ext2 filesystem with the requested parameters.
            self.g.mkfs("ext2", f"/dev/mapper/{mapper}",
                        blocksize=bs, label=label)
            if uuid:
                self.g.set_uuid(f"/dev/mapper/{mapper}", uuid)

        # Mount the root-encrypted LV as the primary root filesystem.
        self.g.mount("/dev/mapper/root-luks", "/")

    # Common LVM root setup
    def _setup_lvm_root(self, device: str) -> None:
        """
        Common helper to create a standard LVM layout on top of `device`.

        The resulting layout is:

            PV: `device`
            VG: "VG"
            LVs:
                - /dev/VG/Root (32 MiB, ext2, blocksize 4096, label ROOT,
                  fixed UUID)
                - /dev/VG/LV1  (32 MiB, ext2, blocksize 4096)
                - /dev/VG/LV2  (32 MiB, ext2, blocksize 1024)
                - /dev/VG/LV3  (64 MiB, ext2, blocksize 2048)

        The Root LV is mounted as the root filesystem at "/" by the end
        of this method.
        """
        # Turn the given device into a PV and create a small VG.
        self.g.pvcreate(device)
        self.g.vgcreate("VG", [device])

        # Create the four LVs with fixed sizes (MiB).
        for name, mib in [("Root", 32), ("LV1", 32), ("LV2", 32), ("LV3", 64)]:
            self.g.lvcreate(name, "VG", mib)

        # Create the ROOT filesystem with a fixed UUID used in tests.
        self.g.mkfs("ext2", "/dev/VG/Root", blocksize=4096, label="ROOT")
        self.g.set_uuid("/dev/VG/Root", "01234567-0123-0123-0123-012345678902")

        # Format the remaining LVs with varying block sizes (test coverage).
        for lv, bs in [("LV1", 4096), ("LV2", 1024), ("LV3", 2048)]:
            self.g.mkfs("ext2", f"/dev/VG/{lv}", blocksize=bs)

        # Mount the root LV as the root filesystem.
        self.g.mount("/dev/VG/Root", "/")
        success("LVM root ready")

    # Populate common files (inspection + test expectations)
    def _populate_common(self) -> None:
        """
        Populate the mounted filesystem with common Fedora-like files.

        This method assumes:

        * The root filesystem is mounted at "/"
        * `self.bootdev` is set to the device that should be used as /boot

        It creates:

        * /boot filesystem with fixed label and UUID
        * /etc/* release files, motd, and basic network config
        * /etc/fstab populated from the temporary fedora.fstab file
        * Optional /etc/mdadm.conf (for MD-based layouts)
        * Minimal RPM database and macros to satisfy inspection tests
        * A small set of test binaries and files in /bin and /etc with
          specific modes, owners and types (regular, symlink, fifo, device)
        * Journald logs unpacked into /var/log/journal
        """
        info("Populating common Fedora test files and structure")

        # Prepare /boot filesystem on the layout-specific boot device.
        self.g.mkfs("ext2", self.bootdev, blocksize=4096, label="boot")
        self.g.set_uuid(self.bootdev, "01234567-0123-0123-0123-012345678901")
        self.g.mkdir("/boot")
        self.g.mount(self.bootdev, "/boot")

        # Create directory structure expected by the tests.
        for d in [
            "/bin", "/etc", "/etc/sysconfig",
            "/usr/share/zoneinfo/Europe",
            "/var/lib/rpm", "/usr/lib/rpm",
            "/var/log/journal", "/boot/grub",
        ]:
            self.g.mkdir_p(d)

        # Basic Fedora identity and system metadata.
        #
        # fedora_version is a free-form string (e.g. "14", "43", "rawhide").
        # We do not attempt to parse or validate it; tests simply match the
        # resulting strings.
        rel = f"Fedora release {self.fedora_version} (Phony)\n"
        motd = f"Welcome to Fedora {self.fedora_version} (Phony)\n"
        self.g.write("/etc/redhat-release", rel)
        self.g.write("/etc/fedora-release", rel)
        self.g.write("/etc/motd", motd)
        self.g.write("/etc/sysconfig/network", "hostname=fedora.invalid\n")

        # fstab and optional mdadm.conf (for MD layouts).
        self.g.upload("fedora.fstab", "/etc/fstab")
        if os.path.exists("fedora.mdadm"):
            self.g.upload("fedora.mdadm", "/etc/mdadm.conf")

        # Minimal RPM database and macros (used by inspection code).
        self.g.upload(str(self.srcdir / "fedora.db"),
                      "/var/lib/rpm/rpmdb.sqlite")
        self.g.touch("/usr/lib/rpm/rpmrc")
        self.g.write(
            "/usr/lib/rpm/macros",
            "%_dbpath /var/lib/rpm\n%_db_backend sqlite\n",
        )

        # Provide a minimal /bin/ls that can be executed inside the guest.
        self.g.upload(str(self.srcdir / "../binaries/bin-x86_64-dynamic"),
                      "/bin/ls")
        self.g.chmod(0o755, "/bin/ls")

        # Import a pre-generated systemd journal so inspection can see
        # realistic log files and metadata.
        self.g.tar_in(str(self.srcdir / "fedora-journal.tar.xz"),
                      "/var/log/journal", compress="xz")

        # Create some small test files with known contents and types.
        for path, content in [
            ("/etc/test1", "ABCDEFG"),
            ("/etc/test2", ""),
            ("/etc/test3", "A\nB\nC\nD\nE\nF\n"),
            ("/bin/test1", "ABCDEFG"),
            ("/bin/test2", "ZXCVBNM"),
            ("/bin/test3", "1234567"),
            ("/bin/test4", ""),
        ]:
            self.g.write(path, content)

        # Ownership, permissions, symlinks, FIFOs, and device nodes.
        # These are used by various tests that check metadata handling.
        self.g.chown(10, 11, "/etc/test3")
        self.g.chmod(0o600, "/etc/test3")
        self.g.ln_s("/bin/test1", "/bin/test5")
        self.g.mkfifo(0o777, "/bin/test6")
        self.g.mknod(0o777, 10, 10, "/bin/test7")
        self.g.touch("/boot/grub/grub.conf")

        success("Common content populated")

    # Public API
    def run(self) -> None:
        """
        Entry point for building the requested layout and populating it.

        This method:

        1. Selects and runs the layout-specific builder based on
           `self.layout`.
        2. Populates the common Fedora content in the resulting guest.
        3. Renames temporary `*.img-t` images into final `.img` files
           inside `self.output_dir`.
        """
        info(f"Building layout: {self.layout.upper()}")

        # Dispatch to the requested layout builder.
        if self.layout == "partitions":
            self._build_partitions()
        elif self.layout == "partitions-md":
            self._build_partitions_md()
        elif self.layout == "btrfs":
            self._build_btrfs()
        elif self.layout == "lvm-on-luks":
            self._build_lvm_on_luks()
        elif self.layout == "luks-on-lvm":
            self._build_luks_on_lvm()
        else:
            error(f"Unknown layout: {self.layout}")

        # At this point, the root filesystem should be mounted at "/"
        # and bootdev set; we now fill in the shared structure.
        self._populate_common()

        # Finalize images: move from temp names (*.img-t) into their
        # final location and name (*.img) under output_dir.
        for img in self.images:
            final = self.output_dir / img[:-2]
            os.rename(img, final)
            success(f"Image ready → {final.name}")


# CLI
#   * manual use from the command line
#   * automated use from Makefiles or CI
#
def main() -> None:
    """
    Parse CLI arguments, perform basic validation, and run the builder.

    This function wires together:

      * argument parsing
      * sanity checks for SRCDIR existence
      * creation and execution of FedoraImageCreator
    """
    parser = argparse.ArgumentParser(
        description="Create Fedora phony guest images for libguestfs tests",
        epilog="Layouts: partitions, partitions-md, btrfs, "
               "lvm-on-luks, luks-on-lvm",
    )

    # `layout` and `srcdir` are required positional arguments.
    parser.add_argument(
        "layout",
        help="Image layout (partitions, partitions-md, btrfs, lvm-on-luks, luks-on-lvm)",
    )
    parser.add_argument(
        "srcdir",
        type=Path,
        help="Directory with test data (e.g. test-data/phony-guests)",
    )
    parser.add_argument(
        "-r",
        "--release",
        "--fedora-version",
        dest="fedora_version",
        default="14",
        help=(
            "Fedora version string to embed in /etc/*release and motd "
            '(e.g. "43", "42", "rawhide"). Default: 14'
        ),
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("."),
        help="Directory in which to place the final images (default: CWD)",
    )

    args = parser.parse_args()

    # Ensure srcdir exists and is a directory.
    if not args.srcdir.is_dir():
        error(f"SRCDIR not a directory: {args.srcdir}")

    # Instantiate the builder and execute it.
    creator = FedoraImageCreator(
        args.layout,
        args.srcdir.resolve(),
        args.output_dir.resolve(),
    )

    # Propagate the requested Fedora version into the creator.
    creator.fedora_version = args.fedora_version

    creator.run()

    print("\nAll done! Ready for libguestfs testing")


if __name__ == "__main__":
    main()
