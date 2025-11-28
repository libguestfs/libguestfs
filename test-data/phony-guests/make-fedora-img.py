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

# With: CLI args + env var fallback, type hints, robust error handling, pathlib,
#  modular structure, verbose control, auto-cleanup.

from __future__ import annotations

import argparse
import atexit
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import NoReturn

import guestfs

# -----------------------------
# Constants
# -----------------------------
IMAGE_SIZE: int = 1024 * 1024 * 1024  # 1 GiB
LEADING_SECTORS: int = 64
TRAILING_SECTORS: int = 64
SECTOR_SIZE: int = 512

PARTITIONS = [
    ["p", LEADING_SECTORS, IMAGE_SIZE // 2 // SECTOR_SIZE - 1],
    ["p", IMAGE_SIZE // 2 // SECTOR_SIZE, -TRAILING_SECTORS],
]

# -----------------------------
# Pretty logging (with verbose control)
# -----------------------------
VERBOSE: bool = False


def log(msg: str) -> None:
    if not VERBOSE:
        return
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"\033[1;36m[{ts}]\033[0m \033[1;33m➤\033[0m {msg}")


def info(msg: str) -> None:
    if not VERBOSE:
        return
    print(f"  \033[1;34mℹ\033[0m {msg}")


def success(msg: str) -> None:
    if not VERBOSE:
        return
    print(f"  \033[1;32m✓\033[0m {msg}")


def warn(msg: str) -> None:
    print(f"  \033[1;33m⚠\033[0m {msg}")


def error(msg: str) -> NoReturn:
    print(f"  \033[1;31m✗\033[0m {msg}", file=sys.stderr)
    sys.exit(1)


# -----------------------------
# Core class for image creation
# -----------------------------
class FedoraImageCreator:
    def __init__(self, layout: str, srcdir: Path, output_dir: Path) -> None:
        self.layout = layout.lower()
        self.srcdir = srcdir
        self.output_dir = output_dir
        self.images: list[str] = []
        self.bootdev: str | None = None
        self.g = guestfs.GuestFS(python_return_dict=True)
        self.g.set_trace(True)
        self.g.set_event_callback(
            lambda ev, eh, buf, arr: info(f"[trace] {buf.strip()}"),
            guestfs.EVENT_TRACE,
        )
        atexit.register(self.cleanup)

    def cleanup(self) -> None:
        try:
            self.g.shutdown()
            self.g.close()
        except Exception as e:
            warn(f"Cleanup error: {e}")
        for tmp in ["fedora.fstab", "fedora.mdadm"]:
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass

    def init_lvm_root(self, rootdev: str) -> None:
        """Initialize uppercase LVM layout (test-compatible)."""
        log(f"Creating LVM on {rootdev}")
        self.g.pvcreate(rootdev)
        self.g.vgcreate("VG", [rootdev])
        for name, size in [("Root", 32), ("LV1", 32), ("LV2", 32), ("LV3", 64)]:
            self.g.lvcreate(name, "VG", size)
            info(f"LV: /dev/VG/{name}")
        self.g.mkfs("ext2", "/dev/VG/Root", blocksize=4096)
        self.g.set_label("/dev/VG/Root", "ROOT")
        self.g.set_uuid("/dev/VG/Root", "01234567-0123-0123-0123-012345678902")
        for lv, bs in [("LV1", 4096), ("LV2", 1024), ("LV3", 2048)]:
            self.g.mkfs("ext2", f"/dev/VG/{lv}", blocksize=bs)
        self.g.mount("/dev/VG/Root", "/")
        success("LVM root ready")

    def build_layout(self) -> None:
        log(f"Building {self.layout.upper()} layout")
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

    def _build_partitions(self) -> None:
        img = "fedora.img-t"
        self.images.append(img)
        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\nLABEL=ROOT / ext2 defaults 0 0\n")
        self.bootdev = "/dev/sda1"
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()
        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)
        self.init_lvm_root("/dev/sda2")

    def _build_partitions_md(self) -> None:
        self.images.extend(["fedora-md1.img-t", "fedora-md2.img-t"])
        with open("fedora.fstab", "w") as f:
            f.write("/dev/md0 /boot ext2 defaults 0 0\nLABEL=ROOT / ext2 defaults 0 0\n")
        self.bootdev = "/dev/md/bootdev"
        for img in self.images:
            self.g.disk_create(img, "raw", IMAGE_SIZE)
            self.g.add_drive(img, format="raw")
        self.g.launch()
        for d in "ab":
            dev = f"/dev/sd{d}"
            self.g.part_init(dev, "mbr")
            for p in PARTITIONS:
                self.g.part_add(dev, *p)
        self.g.md_create("bootdev", ["/dev/sda1", "/dev/sdb1"])
        self.g.md_create("rootdev", ["/dev/sda2", "/dev/sdb2"])
        with open("fedora.mdadm", "w") as f:
            f.write("MAILADDR root\nAUTO +imsm +1.x -all\n")
            for i, name in enumerate(("bootdev", "rootdev")):
                uuid = self.g.md_detail(f"/dev/md/{name}")["uuid"]
                f.write(f"ARRAY /dev/md{i} level=raid1 num-devices=2 UUID={uuid}\n")
        self.init_lvm_root("/dev/md/rootdev")

    def _build_btrfs(self) -> None:
        g2 = guestfs.GuestFS(python_return_dict=True)
        g2.add_drive("/dev/null")
        g2.launch()
        if not g2.feature_available(["btrfs"]):
            warn("Btrfs unavailable → placeholder")
            open("fedora-btrfs.img", "a").close()
            sys.exit(0)
        g2.close()
        img = "fedora-btrfs.img-t"
        self.images.append(img)
        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\n"
                    "LABEL=root / btrfs subvol=root 0 0\n"
                    "LABEL=root /home btrfs subvol=home 0 0\n")
        self.bootdev = "/dev/sda1"
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()
        self.g.part_init("/dev/sda", "mbr")
        self.g.part_add("/dev/sda", "p", 64, 524287)
        self.g.part_add("/dev/sda", "p", 524288, -64)
        self.g.mkfs_btrfs(["/dev/sda2"], label="root")
        self.g.mount("/dev/sda2", "/")
        self.g.btrfs_subvolume_create("/root")
        self.g.btrfs_subvolume_create("/home")
        self.g.umount("/")
        self.g.mount("btrfsvol:/dev/sda2/root", "/")
        self.g.mkdir("/home")  # Test fix
        success("Btrfs ready")

    def _build_lvm_on_luks(self) -> None:
        img = "fedora-lvm-on-luks.img-t"
        self.images.append(img)
        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\nLABEL=ROOT / ext2 defaults 0 0\n")
        self.bootdev = "/dev/sda1"
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()
        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)
        self.g.luks_format("/dev/sda2", "FEDORA", 0)
        self.g.cryptsetup_open("/dev/sda2", "FEDORA", "luks")
        self.init_lvm_root("/dev/mapper/luks")

    def _build_luks_on_lvm(self) -> None:
        img = "fedora-luks-on-lvm.img-t"
        self.images.append(img)
        with open("fedora.fstab", "w") as f:
            f.write("LABEL=boot /boot ext2 defaults 0 0\nLABEL=ROOT / ext2 defaults 0 0\n")
        self.bootdev = "/dev/sda1"
        self.g.disk_create(img, "raw", IMAGE_SIZE)
        self.g.add_drive(img, format="raw")
        self.g.launch()
        self.g.part_init("/dev/sda", "mbr")
        for p in PARTITIONS:
            self.g.part_add("/dev/sda", *p)
        self.g.pvcreate("/dev/sda2")
        self.g.vgcreate("Volume-Group", ["/dev/sda2"])

        lvs = [
            ("Root", 32, "FEDORA-Root", 4096, "ROOT", "01234567-0123-0123-0123-012345678902"),
            ("Logical-Volume-1", 32, "FEDORA-LV1", 4096, "LV1", None),
            ("Logical-Volume-2", 32, "FEDORA-LV2", 1024, "LV2", None),
            ("Logical-Volume-3", 64, "FEDORA-LV3", 2048, "LV3", None),
        ]

        for lv, size, pw, bs, label, uuid_val in lvs:
            self.g.lvcreate(lv, "Volume-Group", size)
            dev = f"/dev/Volume-Group/{lv}"
            self.g.luks_format(dev, pw, 0)
            short_name = "root" if lv == "Root" else f"lv{lv[-1]}"
            mapper = f"{short_name}-luks"
            self.g.cryptsetup_open(dev, pw, mapper)
            info(f"LUKS: {lv} ({pw}) → {mapper}")
            self.g.mkfs("ext2", f"/dev/mapper/{mapper}", blocksize=bs, label=label)
            if uuid_val:
                self.g.set_uuid(f"/dev/mapper/{mapper}", uuid_val)

        self.g.mount("/dev/mapper/root-luks", "/")

    def populate_common(self) -> None:
        """Populate test-compatible common files."""
        log("Populating common content")
        self.g.mkfs("ext2", self.bootdev, blocksize=4096)
        self.g.set_label(self.bootdev, "boot")
        self.g.set_uuid(self.bootdev, "01234567-0123-0123-0123-012345678901")
        self.g.mkdir("/boot")
        self.g.mount(self.bootdev, "/boot")
        dirs = [
            "/bin",
            "/etc",
            "/etc/sysconfig",
            "/usr",
            "/usr/share",
            "/usr/share/zoneinfo",
            "/usr/share/zoneinfo/Europe",
            "/var/lib/rpm",
            "/usr/lib/rpm",
            "/var/log/journal",
        ]
        for d in dirs:
            self.g.mkdir_p(d)
        self.g.touch("/usr/share/zoneinfo/Europe/London")
        self.g.write("/etc/redhat-release", "Fedora release 14 (Phony)\n")
        self.g.write("/etc/fedora-release", "Fedora release 14 (Phony)\n")
        self.g.write("/etc/motd", "Welcome to Fedora 14 (Phony)\n")
        self.g.write("/etc/sysconfig/network", "hostname=fedora.invalid\n")
        self.g.upload("fedora.fstab", "/etc/fstab")
        if os.path.exists("fedora.mdadm"):
            self.g.upload("fedora.mdadm", "/etc/mdadm.conf")
            os.unlink("fedora.mdadm")
        self.g.upload(str(self.srcdir / "fedora.db"), "/var/lib/rpm/rpmdb.sqlite")
        self.g.touch("/usr/lib/rpm/rpmrc")
        self.g.write("/usr/lib/rpm/macros", "%_dbpath /var/lib/rpm\n%_db_backend sqlite\n")
        self.g.upload(str(self.srcdir / "../binaries/bin-x86_64-dynamic"), "/bin/ls")
        self.g.chmod(0o755, "/bin/ls")
        self.g.tar_in(str(self.srcdir / "fedora-journal.tar.xz"), "/var/log/journal", compress="xz")
        self.g.mkdir("/boot/grub")
        self.g.touch("/boot/grub/grub.conf")
        test_files = [
            ("/etc/test1", "ABCDEFG"),
            ("/etc/test2", ""),
            ("/etc/test3", "A\nB\nC\nD\nE\nF\n"),
            ("/bin/test1", "ABCDEFG"),
            ("/bin/test2", "ZXCVBNM"),
            ("/bin/test3", "1234567"),
            ("/bin/test4", ""),
        ]
        for path, content in test_files:
            self.g.write(path, content)
        self.g.chown(10, 11, "/etc/test3")
        self.g.chmod(0o600, "/etc/test3")
        self.g.ln_s("/bin/test1", "/bin/test5")
        self.g.mkfifo(0o777, "/bin/test6")
        self.g.mknod(0o777, 10, 10, "/bin/test7")
        success("Common content populated")

    def finalize(self) -> None:
        log("Finalizing images")
        for img in self.images:
            if img.endswith("-t"):
                final = str(self.output_dir / img[:-2])
                os.rename(img, final)
                success(f"Image ready: {final}")

    def run(self) -> None:
        self.build_layout()
        self.populate_common()
        self.finalize()


# -----------------------------
# CLI parser (with env fallback)
# -----------------------------
def main() -> None:
    global VERBOSE
    parser = argparse.ArgumentParser(
        description="Create Fedora phony guest images for libguestfs tests. 🌟",
        epilog="Layouts: partitions, partitions-md, btrfs, lvm-on-luks, luks-on-lvm",
    )
    parser.add_argument("layout", nargs="?", default=os.environ.get("LAYOUT"), help="Image layout to build (or LAYOUT env var)")
    parser.add_argument("srcdir", nargs="?", default=os.environ.get("SRCDIR"), type=Path, help="Source directory for data files (or SRCDIR env var)")
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("."),
        help="Output directory (default: current)",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable detailed logging")
    args = parser.parse_args()
    VERBOSE = args.verbose

    if not args.layout or not args.srcdir:
        error("LAYOUT and SRCDIR are required (via args or env vars)")
    if not args.srcdir.is_dir():
        error(f"SRCDIR not a directory: {args.srcdir}")

    creator = FedoraImageCreator(args.layout, args.srcdir, args.output_dir)
    creator.run()
    log("\033[1;32mAll done! Ready for libguestfs tests. 🚀\033[0m")


if __name__ == "__main__":
    main()
