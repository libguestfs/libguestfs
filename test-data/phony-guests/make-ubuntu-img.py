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

import argparse
import logging
import os
import shutil
import sys
import tempfile

import guestfs

PROG = os.path.basename(sys.argv[0])
__version__ = "3.0.0"

# version -> (codename, description, root_fs)
UBUNTU_PRESETS = {
    "10.10": ("maverick", "Ubuntu 10.10 (Phony Pharaoh)", "ext2"),
    "20.04": ("focal",   "Ubuntu 20.04 LTS (Focal Fossa)", "ext4"),
    "22.04": ("jammy",   "Ubuntu 22.04 LTS (Jammy Jellyfish)", "ext4"),
    "24.04": ("noble",   "Ubuntu 24.04 LTS (Noble Numbat)", "xfs"),
}

EFI_PART_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"  # UEFI spec ESP type GUID


def ubuntu_metadata(version: str):
    codename, desc, root_fs = UBUNTU_PRESETS.get(
        version,
        ("unknown", f"Ubuntu {version}", "ext4"),
    )
    return codename, desc, root_fs


def make_lsb_release(version: str) -> str:
    codename, desc, _ = ubuntu_metadata(version)
    return (
        "DISTRIB_ID=Ubuntu\n"
        f"DISTRIB_RELEASE={version}\n"
        f"DISTRIB_CODENAME={codename}\n"
        f'DISTRIB_DESCRIPTION="{desc}"\n'
    )


def make_os_release(version: str) -> str:
    codename, desc, _ = ubuntu_metadata(version)
    return (
        'NAME="Ubuntu"\n'
        f'VERSION="{desc}"\n'
        "ID=ubuntu\n"
        f'VERSION_ID="{version}"\n'
        f"VERSION_CODENAME={codename}\n"
        "ID_LIKE=debian\n"
        f'PRETTY_NAME="{desc}"\n'
    )


def make_fstab(root_fs: str) -> str:
    return (
        f"/dev/sda2 / {root_fs} defaults 1 1\n"
        "/dev/sda1 /boot/efi vfat umask=0077 0 1\n"
        "\n"
        "# Dummy encrypted swap device\n"
        "/dev/mapper/cryptswap1 none swap sw 0 0\n"
    )


def parse_size(s: str) -> int:
    s = s.strip().upper()
    if s.endswith("G"):
        return int(float(s[:-1]) * 1024**3)
    if s.endswith("M"):
        return int(float(s[:-1]) * 1024**2)
    if s.endswith("K"):
        return int(float(s[:-1]) * 1024)
    return int(s)


def write_file(path: str, content: str):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def create_temp_metadata(version: str):
    codename, desc, root_fs = ubuntu_metadata(version)

    fstab_path = "ubuntu.fstab"
    lsb_path = "ubuntu.lsb"
    osrel_path = "ubuntu.os"

    write_file(fstab_path, make_fstab(root_fs))
    write_file(lsb_path, make_lsb_release(version))
    write_file(osrel_path, make_os_release(version))

    return fstab_path, lsb_path, osrel_path, root_fs


def add_fake_systemd(g: guestfs.GuestFS):
    # Minimal systemd layout to look more plausible
    g.mkdir_p("/etc/systemd/system")
    g.mkdir_p("/etc/systemd/system/multi-user.target.wants")
    g.mkdir_p("/lib/systemd/system")

    # Fake ssh service
    ssh_unit = (
        "[Unit]\n"
        "Description=Fake OpenSSH server\n"
        "After=network.target\n"
        "\n"
        "[Service]\n"
        "Type=oneshot\n"
        "ExecStart=/bin/true\n"
        "\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n"
    )
    g.write("/etc/systemd/system/ssh.service", ssh_unit)
    g.ln_s("../ssh.service", "/etc/systemd/system/multi-user.target.wants/ssh.service")

    # Fake network service
    net_unit = (
        "[Unit]\n"
        "Description=Fake network setup\n"
        "Before=network-online.target\n"
        "\n"
        "[Service]\n"
        "Type=oneshot\n"
        "ExecStart=/bin/true\n"
        "\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n"
    )
    g.write("/etc/systemd/system/fake-network.service", net_unit)
    g.ln_s(
        "../fake-network.service",
        "/etc/systemd/system/multi-user.target.wants/fake-network.service",
    )

    # Default target (multi-user) – very hand-wavy but good enough
    g.write(
        "/lib/systemd/system/multi-user.target",
        "[Unit]\nDescription=Fake multi-user target\n",
    )
    g.ln_s(
        "/lib/systemd/system/multi-user.target",
        "/etc/systemd/system/default.target",
    )


def build_image(output: str, size: int, srcdir: str, ubuntu_version: str, verbose: bool):
    logging.info("Building Ubuntu %s image → %s", ubuntu_version, output)

    fstab_path = lsb_path = osrel_path = None
    tmpimg = None

    try:
        fstab_path, lsb_path, osrel_path, root_fs = create_temp_metadata(ubuntu_version)

        fd, tmpimg = tempfile.mkstemp(prefix="ubuntu-efi-")
        os.close(fd)

        g = guestfs.GuestFS(python_return_dict=True)
        g.disk_create(filename=tmpimg,
                      format="raw",
                      size=size,
                      preallocation="sparse",
                 )

        g.add_drive_opts(tmpimg, format="raw", readonly=0)
        g.launch()

        # GPT + EFI
        g.part_init("/dev/sda", "gpt")
        # 200MB ESP: start at 2048, end at 411647 (in sectors)
        g.part_add("/dev/sda", "p", 2048, 411647)
        # Root: rest of disk, leaving GPT metadata at end
        g.part_add("/dev/sda", "p", 411648, -34)

        # Mark partition 1 as EFI System Partition
        g.part_set_gpt_type("/dev/sda", 1, EFI_PART_GUID)

        # Format ESP
        g.mkfs("vfat", "/dev/sda1")

        # Root filesystem type varies by Ubuntu vintage
        if root_fs == "xfs":
            g.mkfs("xfs", "/dev/sda2")
        elif root_fs == "ext2":
            g.mkfs("ext2", "/dev/sda2")
        else:
            g.mkfs("ext4", "/dev/sda2")

        # Mount root and ESP
        g.mount("/dev/sda2", "/")
        g.mkdir_p("/boot/efi")
        g.mkdir_p("/boot")
        g.mount("/dev/sda1", "/boot/efi")

        # Basic tree
        for d in ("/bin", "/etc", "/usr", "/home"):
            g.mkdir(d)
        g.mkdir_p("/var/lib/dpkg")
        g.mkdir_p("/boot/grub")
        g.mkdir_p("/boot/efi/EFI/ubuntu")

        # Upload metadata
        g.upload(fstab_path, "/etc/fstab")
        g.upload(lsb_path, "/etc/lsb-release")
        g.upload(osrel_path, "/etc/os-release")
        g.write("/etc/hostname", "ubuntu.invalid")
        g.write("/etc/debian_version", "12")

        # dpkg status
        dpkg_status = os.path.join(srcdir, "debian-packages")
        if not os.path.exists(dpkg_status):
            raise RuntimeError(f"missing debian-packages at {dpkg_status}")
        g.upload(dpkg_status, "/var/lib/dpkg/status")

        # Fake /bin/ls
        ls_bin = os.path.normpath(
            os.path.join(srcdir, "..", "binaries", "bin-x86_64-dynamic")
        )
        if not os.path.exists(ls_bin):
            raise RuntimeError(f"missing ls binary at {ls_bin}")
        g.upload(ls_bin, "/bin/ls")
        g.chmod(0o755, "/bin/ls")

        # Fake EFI grub stub
        g.write("/boot/efi/EFI/ubuntu/grub.cfg", "# fake EFI grub config\n")
        g.touch("/boot/grub/grub.cfg")

        # Fake systemd units
        add_fake_systemd(g)

        g.sync()
        g.umount_all()
        g.shutdown()
        g.close()

        shutil.move(tmpimg, output)
        logging.info("Image created successfully")

    finally:
        for p in (fstab_path, lsb_path, osrel_path):
            if p and os.path.exists(p):
                try:
                    os.unlink(p)
                except OSError:
                    pass
        if tmpimg and os.path.exists(tmpimg):
            try:
                os.unlink(tmpimg)
            except OSError:
                pass


def main():
    ap = argparse.ArgumentParser(
        prog=PROG,
        description="Create a fake EFI Ubuntu disk image for libguestfs inspection",
    )
    ap.add_argument("-o", "--output", default="ubuntu-efi.img",
                    help="Output image filename (default: %(default)s)")
    ap.add_argument("-s", "--size", default="2G",
                    help="Disk size, e.g. 2G, 512M (default: %(default)s)")
    ap.add_argument("-r", "--ubuntu-version", default="22.04",
                    help="Ubuntu version to emulate, e.g. 20.04, 22.04, 24.04 (default: %(default)s)")
    ap.add_argument("-S", "--srcdir", default=os.environ.get("SRCDIR", "."),
                    help="Source dir containing debian-packages and ../binaries/bin-x86_64-dynamic")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="Verbose logging")
    ap.add_argument("--version", action="version",
                    version=f"%(prog)s {__version__}")

    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    size_bytes = parse_size(args.size)
    build_image(args.output, size_bytes, args.srcdir, args.ubuntu_version, args.verbose)


if __name__ == "__main__":
    main()
