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
Make an Arch Linux image which is enough to fool the inspection heuristics.
Re-implementation of the original guestfish shell script in Python using the
libguestfs Python bindings, with some nice extras:
- CLI options (output path, size, srcdir, EFI toggle)
- Optional EFI-aware layout (GPT + ESP + root)
"""
import argparse
import os
import sys
import tempfile
import guestfs
# Defaults roughly matching the original script.
DEFAULT_IMAGE_NAME = "archlinux.img"
DEFAULT_SIZE_MB = 512 # 512 MiB
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a tiny Arch Linux image sufficient to fool libguestfs inspection."
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="PATH",
        default=DEFAULT_IMAGE_NAME,
        help=f"Output disk image filename (default: {DEFAULT_IMAGE_NAME})",
    )
    parser.add_argument(
        "-s",
        "--size-mb",
        type=int,
        default=DEFAULT_SIZE_MB,
        help=f"Disk size in MiB (default: {DEFAULT_SIZE_MB})",
    )
    parser.add_argument(
        "--srcdir",
        metavar="DIR",
        default=".",
        help="Source tree directory containing 'archlinux-package' and '../binaries/bin-x86_64-dynamic' "
             "(default: current directory)",
    )
    parser.add_argument(
        "--efi",
        dest="use_efi",
        action="store_true",
        help="Create a GPT + EFI System Partition + ext4 root layout.",
    )
    parser.add_argument(
        "--no-efi",
        dest="use_efi",
        action="store_false",
        help="Create legacy MBR + single ext4 root partition (default).",
    )
    parser.set_defaults(use_efi=False)
    return parser.parse_args()
def create_sparse_file(path: str, size_bytes: int) -> None:
    """Create a sparse file of the requested size."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    try:
        os.ftruncate(fd, size_bytes)
    finally:
        os.close(fd)
def create_fstab_content(use_efi: bool) -> str:
    """
    Generate /etc/fstab content.
    For EFI:
      - LABEL=EFI mounted on /boot/efi
      - /dev/sda2 as root
    For non-EFI:
      - /dev/sda1 as root
    """
    lines = []
    if use_efi:
        lines.append("LABEL=EFI /boot/efi vfat umask=0077 0 1")
        root_dev = "/dev/sda2"
    else:
        root_dev = "/dev/sda1"
    # Match the intent of the original script: ext4 root with typical Arch options.
    lines.append(f"{root_dev} / ext4 rw,relatime,data=ordered 0 1")
    return "\n".join(lines) + "\n"
def setup_partitions(g: guestfs.GuestFS, use_efi: bool) -> None:
    """
    Create partitions and filesystems.
    For non-EFI:
      - MBR
      - sda1: single ext4 partition (like original shell script)
    For EFI:
      - GPT
      - sda1: EFI System Partition (vfat)
      - sda2: ext4 root
    """
    if use_efi:
        # GPT with ESP + root.
        g.part_init("/dev/sda", "gpt")
        # Use typical GPT layout:
        # - First usable sector: 2048
        # - Leave a small gap at the end; -34 is the usual "to end-34" trick.
        #
        # For a 512 MiB disk this is overkill but it's fine for a test image.
        #
        # ESP: first ~100 MiB (in sectors)
        esp_start = 2048
        esp_end = esp_start + (100 * 1024 * 1024 // 512) - 1
        g.part_add("/dev/sda", "p", esp_start, esp_end)
        # Root: rest of the disk.
        g.part_add("/dev/sda", "p", esp_end + 1, -34)
        g.part_set_bootable("/dev/sda", 1, True)
        # Re-read partition table
        g.blockdev_flushbufs("/dev/sda")
        g.blockdev_rereadpt("/dev/sda")
        # Filesystems
        g.mkfs("vfat", "/dev/sda1")
        g.set_label("/dev/sda1", "EFI")
        # ext4 root; keep the UUID from the original script for fun.
        g.mkfs("ext4", "/dev/sda2", blocksize=4096)
        g.set_uuid("/dev/sda2", "01234567-0123-0123-0123-012345678902")
    else:
        # Original layout: MBR, single ext4 partition.
        g.part_init("/dev/sda", "mbr")
        g.part_add("/dev/sda", "p", 64, -64)
        g.part_set_bootable("/dev/sda", 1, True)
        # Re-read partition table
        g.blockdev_flushbufs("/dev/sda")
        g.blockdev_rereadpt("/dev/sda")
        g.mkfs("ext4", "/dev/sda1", blocksize=4096)
        g.set_uuid("/dev/sda1", "01234567-0123-0123-0123-012345678902")
def populate_filesystem(g: guestfs.GuestFS, srcdir: str, use_efi: bool) -> None:
    """Create directories, config files, and upload fake Arch bits."""
    # Mount root filesystem.
    if use_efi:
        g.mount("/dev/sda2", "/")
        g.mkdir_p("/boot/efi")
        g.mount("/dev/sda1", "/boot/efi")
    else:
        g.mount("/dev/sda1", "/")
    # Basic directory tree.
    g.mkdir("/boot")
    g.mkdir("/bin")
    g.mkdir("/etc")
    g.mkdir("/home")
    g.mkdir("/usr")
    g.mkdir_p("/var/lib/pacman/local/test-package-1:0.1-1")
    # /etc/fstab
    fstab = create_fstab_content(use_efi)
    g.write("/etc/fstab", fstab)
    # Arch-specific markers.
    g.write("/etc/arch-release", "Arch Linux\n")
    g.write("/etc/hostname", "archlinux.test\n")
    # Fake pacman package metadata.
    arch_pkg = os.path.join(srcdir, "archlinux-package")
    if not os.path.exists(arch_pkg):
        raise FileNotFoundError(f"Cannot find archlinux-package at {arch_pkg}")
    g.upload(arch_pkg, "/var/lib/pacman/local/test-package-1:0.1-1/desc")
    # Fake /bin/ls binary.
    ls_binary = os.path.join(srcdir, "..", "binaries", "bin-x86_64-dynamic")
    if not os.path.exists(ls_binary):
        raise FileNotFoundError(f"Cannot find test ls binary at {ls_binary}")
    g.upload(ls_binary, "/bin/ls")
    g.chmod(0o755, "/bin/ls")
    # Bootloader crumbs: enough to tick inspection heuristics.
    g.mkdir_p("/boot/grub")
    # Old-style grub.conf and new-style grub.cfg, just empty placeholders.
    g.write("/boot/grub/grub.conf", "")
    g.write("/boot/grub/grub.cfg", "")
    if use_efi:
        # Minimal EFI directory structure, even if it's empty.
        g.mkdir_p("/boot/efi/EFI/BOOT")
        # A placeholder file helps some naive heuristics.
        g.write("/boot/efi/EFI/BOOT/BOOTX64.EFI", "")
def create_archlinux_image(output_filename: str, size_mb: int, srcdir: str, use_efi: bool) -> None:
    size_bytes = size_mb * 1024 * 1024
    # Create a temporary sparse image and then rename it to the final name.
    # This mimics the original "archlinux.img-t" + mv dance.
    tmp_dir = os.path.dirname(os.path.abspath(output_filename)) or "."
    tmp_fd, tmp_path = tempfile.mkstemp(
        prefix="archlinux.img-",
        dir=tmp_dir,
    )
    os.close(tmp_fd) # We will re-use the path only.
    try:
        create_sparse_file(tmp_path, size_bytes)
        g = guestfs.GuestFS(python_return_dict=True)
        g.add_drive_opts(tmp_path, format="raw", readonly=0)
        g.launch()
        setup_partitions(g, use_efi)
        populate_filesystem(g, srcdir, use_efi)
        g.sync()
        g.umount_all()
        g.shutdown()
        g.close()
        # All good: rename temp to final output.
        if os.path.exists(output_filename):
            os.remove(output_filename)
        os.rename(tmp_path, output_filename)
    except Exception:
        # On error, clean up the temp file to avoid leaving junk behind.
        try:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        except Exception:
            pass
        raise
def main() -> None:
    args = parse_args()
    try:
        create_archlinux_image(
            output_filename=args.output,
            size_mb=args.size_mb,
            srcdir=args.srcdir,
            use_efi=args.use_efi,
        )
    except Exception as ex:
        print(f"Error creating Arch Linux image: {ex}", file=sys.stderr)
        sys.exit(1)
if __name__ == "__main__":
    main()
