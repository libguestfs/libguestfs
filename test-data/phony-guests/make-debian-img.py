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
Create a tiny fake Debian disk image that is "good enough" to fool
libguestfs inspection heuristics.

Supports:
  - Legacy BIOS/MBR layout
  - EFI/GPT layout with ESP
  - Simple LVM layout with a few logical volumes
"""

import argparse
import logging
import os
import sys
from typing import Dict, Optional

try:
    import guestfs  # type: ignore
except ImportError as e:
    print("Error: The 'guestfs' Python module is not installed.")
    print("On Debian/Ubuntu, try: sudo apt install python3-guestfs")
    sys.exit(1)


# Defaults / configuration
DEFAULT_VERSION = "12.0"          # Debian Bookworm-ish
DEFAULT_IMAGE_NAME = "debian.img"
DEFAULT_IMAGE_SIZE_MB = 512       # 512 MB


# Hard-coded UUIDs purely to make inspection deterministic.
BOOT_UUID = "01234567-0123-0123-0123-012345678901"
LV_UUIDS: Dict[str, str] = {
    "root": "01234567-0123-0123-0123-012345678902",
    "usr":  "01234567-0123-0123-0123-012345678903",
    "var":  "01234567-0123-0123-0123-012345678904",
    "home": "01234567-0123-0123-0123-012345678905",
}


def create_fstab_content(use_efi: bool) -> str:
    """Generate /etc/fstab contents."""
    lines = []

    if use_efi:
        lines.append("LABEL=EFI /boot/efi vfat umask=0077 0 1")
        lines.append("LABEL=BOOT /boot ext2 default 0 0")
    else:
        lines.append("LABEL=BOOT /boot ext2 default 0 0")

    lines.extend(
        [
            "/dev/debian/root / ext2 default 0 0",
            "/dev/debian/usr  /usr ext2 default 1 2",
            "/dev/debian/var  /var ext2 default 1 2",
            "/dev/debian/home /home ext2 default 1 2",
        ]
    )

    return "\n".join(lines) + "\n"


def init_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(levelname)s: %(message)s",
    )


def create_sparse_image(path: str, size_mb: int) -> None:
    """Create (or overwrite) a sparse image file of given size in MB."""
    if os.path.exists(path):
        logging.debug("Removing existing image: %s", path)
        os.unlink(path)

    size_bytes = size_mb * 1024 * 1024
    logging.info("Creating sparse image %s (%d MB)", path, size_mb)
    with open(path, "wb") as f:
        f.truncate(size_bytes)


def setup_partitions(g: "guestfs.GuestFS", use_efi: bool) -> Dict[str, Optional[str]]:
    """
    Create partitions and return a dict with:
        boot_device, lvm_device, efi_device (efi_device is None for MBR)
    """
    # We assume 512-byte sectors; sector calculations mirror your original layout.
    if use_efi:
        logging.info("Setting up GPT partition table for EFI")
        g.part_init("/dev/sda", "gpt")

        # 1) EFI System Partition (ESP): 100 MB starting at sector 2048.
        #    100MB / 512B = 204800 sectors
        esp_start = 2048
        esp_end = esp_start + 204800 - 1
        g.part_add("/dev/sda", "p", esp_start, esp_end)
        g.part_set_name("/dev/sda", 1, "EFI System Partition")
        g.part_set_bootable("/dev/sda", 1, True)

        # 2) Boot partition: 256 MB
        boot_start = esp_end + 1
        boot_sectors = (256 * 1024 * 1024) // 512
        boot_end = boot_start + boot_sectors - 1
        g.part_add("/dev/sda", "p", boot_start, boot_end)
        g.part_set_name("/dev/sda", 2, "Linux Boot")

        # 3) LVM partition: rest of disk
        lvm_start = boot_end + 1
        g.part_add("/dev/sda", "p", lvm_start, -2048)
        g.part_set_name("/dev/sda", 3, "Linux LVM")

        return {
            "boot_device": "/dev/sda2",
            "lvm_device": "/dev/sda3",
            "efi_device": "/dev/sda1",
        }

    logging.info("Setting up MBR partition table for BIOS/legacy boot")
    g.part_init("/dev/sda", "mbr")

    # Boot partition: sectors [64, 524287]
    g.part_add("/dev/sda", "p", 64, 524287)
    # LVM partition: from 524288 to near end
    g.part_add("/dev/sda", "p", 524288, -64)

    return {
        "boot_device": "/dev/sda1",
        "lvm_device": "/dev/sda2",
        "efi_device": None,
    }


def setup_lvm(g: "guestfs.GuestFS", lvm_device: str) -> None:
    """Create a simple LVM layout with a few logical volumes."""
    logging.info("Creating LVM PV/VG/LVs on %s", lvm_device)
    g.pvcreate(lvm_device)
    g.vgcreate("debian", [lvm_device])

    # Sizes in MB. Small but enough to look plausible.
    lv_sizes = {
        "root": 64,
        "usr": 32,
        "var": 32,
        "home": 32,
    }

    for name, size_mb in lv_sizes.items():
        logging.debug("Creating LV %s (%d MB)", name, size_mb)
        g.lvcreate(name, "debian", size_mb)


def mkfs_and_mount(
    g: "guestfs.GuestFS",
    boot_device: str,
    efi_device: Optional[str],
    use_efi: bool,
) -> None:
    """Create filesystems and mount them in their expected locations."""
    logging.info("Creating filesystems")

    # Boot
    g.mkfs("ext2", boot_device, blocksize=4096, label="BOOT")
    g.set_uuid(boot_device, BOOT_UUID)

    # EFI
    if use_efi and efi_device is not None:
        logging.debug("Creating EFI vfat filesystem on %s", efi_device)
        g.mkfs("vfat", efi_device, label="EFI")

    # Logical volumes
    for lv_name, uuid in LV_UUIDS.items():
        dev = f"/dev/debian/{lv_name}"
        logging.debug("Creating ext2 filesystem on %s", dev)
        g.mkfs("ext2", dev, blocksize=4096)
        g.set_uuid(dev, uuid)

    # Mount everything
    logging.info("Mounting filesystems")
    g.mount("/dev/debian/root", "/")

    g.mkdir("/boot")
    g.mount(boot_device, "/boot")

    if use_efi and efi_device is not None:
        g.mkdir("/boot/efi")
        g.mount(efi_device, "/boot/efi")

    g.mkdir("/usr")
    g.mount("/dev/debian/usr", "/usr")

    g.mkdir("/var")
    g.mount("/dev/debian/var", "/var")

    g.mkdir("/home")
    g.mount("/dev/debian/home", "/home")


def populate_files(g: "guestfs.GuestFS", debian_version: str, use_efi: bool) -> None:
    """Create minimal file/dir tree to look like a Debian system."""
    logging.info("Populating filesystem with minimal Debian markers")

    # Basic dirs
    g.mkdir("/bin")
    g.mkdir("/etc")
    g.mkdir_p("/var/lib/dpkg")
    g.mkdir_p("/var/lib/urandom")
    g.mkdir("/var/log")

    # /etc/fstab
    g.write("/etc/fstab", create_fstab_content(use_efi))

    # /etc/debian_version
    g.write("/etc/debian_version", debian_version + "\n")

    # /etc/hostname
    g.write("/etc/hostname", "debian.invalid\n")

    # /var/lib/dpkg/status – enough to convince inspection it's Debian
    dpkg_status = """Package: bash
Status: install ok installed
Priority: required
Section: shells
Installed-Size: 3000
Maintainer: Debian Bash Maintainers <pkg-bash-maint@lists.alioth.debian.org>
Architecture: amd64
Version: 5.2.15-2+b2
Description: GNU Bourne Again SHell
"""
    g.write("/var/lib/dpkg/status", dpkg_status)

    # /bin/ls – fake ELF header; we don't care if it's executable, just present
    fake_elf = b"\x7fELF" + b"\x00" * 100
    g.write("/bin/ls", fake_elf)
    g.chmod(0o755, "/bin/ls")

    # /var/log/syslog – makes it look less empty
    syslog_line = (
        "Dec 10 12:00:00 debian systemd[1]: Started System Logging Service.\n"
    )
    g.write("/var/log/syslog", syslog_line)

    # Grub config placeholders
    g.mkdir("/boot/grub")
    g.touch("/boot/grub/grub.conf")
    if use_efi:
        g.touch("/boot/grub/grub.cfg")


def create_debian_image(
    output_filename: str,
    debian_version: str,
    use_efi: bool,
    size_mb: int,
) -> None:
    """Top-level function: create the fake Debian image."""
    create_sparse_image(output_filename, size_mb)

    logging.info("Debian version: %s", debian_version)
    logging.info("Boot mode: %s", "EFI/GPT" if use_efi else "BIOS/MBR")

    g = guestfs.GuestFS(python_return_dict=True)

    try:
        g.add_drive_opts(output_filename, format="raw", readonly=0)
        g.launch()

        layout = setup_partitions(g, use_efi)
        boot_device = layout["boot_device"]
        lvm_device = layout["lvm_device"]
        efi_device = layout["efi_device"]

        if not boot_device or not lvm_device:
            raise RuntimeError("Partition setup did not return expected devices")

        setup_lvm(g, lvm_device)
        mkfs_and_mount(g, boot_device, efi_device, use_efi)
        populate_files(g, debian_version, use_efi)

        logging.info("Image creation completed successfully: %s", output_filename)
    finally:
        # Make sure the appliance is torn down cleanly
        try:
            g.umount_all()
        except Exception:
            # Ignore unmount errors in teardown
            pass

        try:
            g.shutdown()
        except Exception:
            pass

        g.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a dummy Debian disk image for libguestfs testing.",
    )

    parser.add_argument(
        "--version",
        type=str,
        default=DEFAULT_VERSION,
        help=f"Debian version string for /etc/debian_version (default: {DEFAULT_VERSION})",
    )

    parser.add_argument(
        "--output",
        type=str,
        default=DEFAULT_IMAGE_NAME,
        help=f"Output filename (default: {DEFAULT_IMAGE_NAME})",
    )

    parser.add_argument(
        "--efi",
        action="store_true",
        help="Use EFI partitioning (GPT + ESP) instead of legacy MBR",
    )

    parser.add_argument(
        "--size-mb",
        type=int,
        default=DEFAULT_IMAGE_SIZE_MB,
        help=f"Image size in MB (default: {DEFAULT_IMAGE_SIZE_MB})",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()
    init_logging(args.verbose)

    try:
        create_debian_image(
            output_filename=args.output,
            debian_version=args.version,
            use_efi=args.efi,
            size_mb=args.size_mb,
        )
    except Exception as e:
        logging.error("Image creation failed: %s", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
