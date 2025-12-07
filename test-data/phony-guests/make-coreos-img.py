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
make_coreos_img.py

- Writes a CoreOS-style /usr/lib/os-release (coreos.release).
- Enough to make libguestfs inspection think "CoreOS/Container Linux".

Extras:
  - --latest: use latest known Container Linux stable (2512.3.0).
  - --version/--build-id/--pretty-name for arbitrary releases.
  - --image-size/--output/--hostname/--update-group from CLI.
  - --dry-run to inspect guestfish script without running it.
"""

from __future__ import annotations

import argparse
import dataclasses
import logging
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from textwrap import dedent
from typing import Optional

DEFAULT_IMAGE_SIZE = "512M"
DEFAULT_OUTPUT = "coreos.img"

DEFAULT_VERSION = "899.13.0"
DEFAULT_BUILD_ID = "2016-03-23-0120"

# Latest stable Container Linux (EOL, but historically last). :contentReference[oaicite:1]{index=1}
LATEST_CL_VERSION = "2512.3.0"
LATEST_CL_BUILD_ID = "2020-05-22"

DEFAULT_UPDATE_GROUP = "stable"
DEFAULT_HOSTNAME = "coreos.invalid"

DEFAULT_USR_UUID = "01234567-0123-0123-0123-012345678901"
DEFAULT_ROOT_UUID = "01234567-0123-0123-0123-012345678902"


class ImageBuildError(RuntimeError):
    """Something went wrong while building the image."""


@dataclasses.dataclass(slots=True)
class Config:
    # IO / behaviour
    output: Path
    image_size: str
    guestfish: str
    force: bool
    dry_run: bool

    # os-release / CoreOS metadata
    name: str
    os_id: str
    version: str
    version_id: str
    build_id: str
    pretty_name: str
    ansi_color: str
    home_url: str
    bug_report_url: str

    # misc config
    update_group: str
    hostname: str
    usr_uuid: str
    root_uuid: str

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> Config:
        output = Path(args.output).resolve()

        # Decide VERSION / BUILD_ID
        if args.latest:
            version = LATEST_CL_VERSION
            build_id = LATEST_CL_BUILD_ID
        else:
            version = args.version
            build_id = args.build_id

        version_id = args.version_id or version
        pretty_name = args.pretty_name or f"CoreOS {version}"

        # guestfish can be overridden by env, then CLI, then plain 'guestfish'
        guestfish = (
            args.guestfish
            or os.environ.get("GUESTFISH")
            or "guestfish"
        )

        return cls(
            output=output,
            image_size=args.image_size,
            guestfish=guestfish,
            force=args.force,
            dry_run=args.dry_run,
            name=args.os_name,
            os_id=args.os_id,
            version=version,
            version_id=version_id,
            build_id=build_id,
            pretty_name=pretty_name,
            ansi_color="1;32",
            home_url=args.home_url,
            bug_report_url=args.bug_report_url,
            update_group=args.update_group,
            hostname=args.hostname,
            usr_uuid=args.usr_uuid,
            root_uuid=args.root_uuid,
        )


def build_coreos_release(cfg: Config) -> str:
    """Return the content of the coreos.release / os-release file."""
    return (
        dedent(
            f"""\
            NAME={cfg.name}
            ID={cfg.os_id}
            VERSION={cfg.version}
            VERSION_ID={cfg.version_id}
            BUILD_ID={cfg.build_id}
            PRETTY_NAME="{cfg.pretty_name}"
            ANSI_COLOR="{cfg.ansi_color}"
            HOME_URL="{cfg.home_url}"
            BUG_REPORT_URL="{cfg.bug_report_url}"
            """
        ).rstrip()
        + "\n"
    )


def build_guestfish_script(
    cfg: Config,
    *,
    coreos_release_path: Path,
    tmp_image_path: Path,
) -> str:
    """
    Construct the guestfish script.

    Matches the original layout:

      /dev/sda1: EFI_SYSTEM (FAT)
      /dev/sda2: BIOS-BOOT
      /dev/sda3: USR-A (ext4)
      /dev/sda4: USR-B (ext4, unused)
      /dev/sda5: ROOT (ext4)
    """
    img = str(tmp_image_path)
    coreos_release = str(coreos_release_path)

    lines: list[str] = [
        f"sparse {img} {cfg.image_size}",
        "run",
        "",
        "# Partition table: GPT with five partitions.",
        "part-init /dev/sda gpt",
        "part-add /dev/sda p 4096 266239",
        "part-add /dev/sda p 266240 270335",
        "part-add /dev/sda p 270336 532479",
        "part-add /dev/sda p 532480 794623",
        "part-add /dev/sda p 794624 -4096",
        "",
        "part-set-name /dev/sda 1 EFI_SYSTEM",
        "part-set-bootable /dev/sda 1 true",
        "part-set-name /dev/sda 2 BIOS-BOOT",
        "part-set-name /dev/sda 3 USR-A",
        "part-set-name /dev/sda 4 USR-B",
        "part-set-name /dev/sda 5 ROOT",
        "",
        "# Filesystems.",
        "mkfs fat /dev/sda1",
        "mkfs ext4 /dev/sda3",
        "set-label /dev/sda3 USR-A",
        f"set-uuid /dev/sda3 {cfg.usr_uuid}",
        "mkfs ext4 /dev/sda5",
        "set-label /dev/sda5 ROOT",
        f"set-uuid /dev/sda5 {cfg.root_uuid}",
        "",
        "# Enough to fool inspection.",
        "mount /dev/sda5 /",
        "mkdir-p /etc/coreos",
        "mkdir /usr",
        "mount /dev/sda3 /usr",
        "mkdir /usr/bin",
        "mkdir /usr/lib64",
        "mkdir /usr/local",
        "mkdir-p /usr/share/coreos/",
        "",
        "ln-s usr/bin /bin",
        "ln-s usr/lib64 /lib64",
        "ln-s lib64 /lib",
        "ln-s lib64 /usr/lib",
        "mkdir /root",
        "mkdir /home",
        "",
        f'write /etc/coreos/update.conf "GROUP={cfg.update_group}"',
        f"upload {coreos_release} /usr/lib/os-release",
        "ln-s ../usr/lib/os-release /etc/os-release",
        f'write /etc/hostname "{cfg.hostname}"',
    ]

    return "\n".join(lines) + "\n"


def check_guestfish(guestfish: str) -> None:
    """Ensure guestfish is available on PATH (unless dry-run)."""
    if shutil.which(guestfish) is None:
        raise ImageBuildError(
            f"guestfish binary '{guestfish}' was not found on PATH. "
            "Install libguestfs-tools or specify --guestfish."
        )


def run_guestfish(guestfish: str, script: str) -> None:
    """Run guestfish with the provided script on stdin."""
    try:
        subprocess.run(
            [guestfish],
            input=script,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ImageBuildError(
            f"guestfish failed with exit code {exc.returncode}"
        ) from exc


def ensure_output_path(cfg: Config, tmp_image_path: Path) -> None:
    """Handle existing output image, and move tmp -> final."""
    if cfg.output.exists():
        if cfg.force:
            logging.warning("Overwriting existing image: %s", cfg.output)
            cfg.output.unlink()
        else:
            raise ImageBuildError(
                f"Output image {cfg.output} already exists. Use --force to overwrite."
            )

    cfg.output.parent.mkdir(parents=True, exist_ok=True)
    tmp_image_path.rename(cfg.output)
    logging.info("Created image: %s", cfg.output)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a minimal CoreOS/Container Linux-like image using guestfish.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    # IO / general
    parser.add_argument(
        "-o",
        "--output",
        default=DEFAULT_OUTPUT,
        help="Output disk image path.",
    )
    parser.add_argument(
        "--image-size",
        default=DEFAULT_IMAGE_SIZE,
        help="Size of the sparse image, in guestfish size format (e.g. 512M).",
    )
    parser.add_argument(
        "--guestfish",
        default=None,
        help="Path to the guestfish binary "
             "(or use $GUESTFISH, defaults to 'guestfish').",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="Overwrite output image if it already exists.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not run guestfish; just print os-release and the guestfish script.",
    )

    # os-release / CoreOS metadata
    parser.add_argument(
        "--latest",
        action="store_true",
        help=(
            "Use latest known Container Linux stable version "
            f"({LATEST_CL_VERSION}) for VERSION/PRETTY_NAME/BUILD_ID."
        ),
    )
    parser.add_argument(
        "--version",
        default=DEFAULT_VERSION,
        help="CoreOS VERSION string (ignored if --latest is set).",
    )
    parser.add_argument(
        "--version-id",
        default=None,
        help="CoreOS VERSION_ID string (defaults to --version or latest).",
    )
    parser.add_argument(
        "--build-id",
        default=DEFAULT_BUILD_ID,
        help="CoreOS BUILD_ID string (overridden by --latest).",
    )
    parser.add_argument(
        "--pretty-name",
        default=None,
        help='PRETTY_NAME for os-release (defaults to "CoreOS <version>").',
    )
    parser.add_argument(
        "--os-name",
        default="CoreOS",
        help="NAME field in os-release.",
    )
    parser.add_argument(
        "--os-id",
        default="coreos",
        help="ID field in os-release.",
    )
    parser.add_argument(
        "--home-url",
        default="https://coreos.com/",
        help="HOME_URL for os-release.",
    )
    parser.add_argument(
        "--bug-report-url",
        default="https://github.com/coreos/bugs/issues",
        help="BUG_REPORT_URL for os-release.",
    )

    # Misc configuration
    parser.add_argument(
        "--update-group",
        default=DEFAULT_UPDATE_GROUP,
        help="Update group written to /etc/coreos/update.conf.",
    )
    parser.add_argument(
        "--hostname",
        default=DEFAULT_HOSTNAME,
        help="Hostname to write to /etc/hostname.",
    )
    parser.add_argument(
        "--usr-uuid",
        default=DEFAULT_USR_UUID,
        help="UUID for the USR-A filesystem (sda3).",
    )
    parser.add_argument(
        "--root-uuid",
        default=DEFAULT_ROOT_UUID,
        help="UUID for the ROOT filesystem (sda5).",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Increase logging verbosity (can be used multiple times).",
    )

    return parser.parse_args(argv)


def setup_logging(verbosity: int) -> None:
    if verbosity >= 2:
        level = logging.DEBUG
    elif verbosity == 1:
        level = logging.INFO
    else:
        level = logging.WARNING

    logging.basicConfig(
        level=level,
        format="%(levelname)s: %(message)s",
    )


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    setup_logging(args.verbose)

    cfg = Config.from_args(args)
    logging.debug("Using config: %r", cfg)

    coreos_release_content = build_coreos_release(cfg)

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)

        # Temporary coreos release
        coreos_release_path = tmpdir / "coreos.release"
        coreos_release_path.write_text(coreos_release_content, encoding="utf-8")
        logging.info("Generated os-release at %s", coreos_release_path)

        # Match shell style: "coreos.img-t" then rename to "coreos.img".
        tmp_image_path = cfg.output.with_name(cfg.output.name + "-t")

        guestfish_script = build_guestfish_script(
            cfg,
            coreos_release_path=coreos_release_path,
            tmp_image_path=tmp_image_path,
        )

        if cfg.dry_run:
            print("# --- coreos.release ---")
            print(coreos_release_content)
            print("# --- guestfish script ---")
            print(guestfish_script)
            return 0

        try:
            check_guestfish(cfg.guestfish)
            run_guestfish(cfg.guestfish, guestfish_script)
            ensure_output_path(cfg, tmp_image_path)
        except ImageBuildError as exc:
            logging.error("%s", exc)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
