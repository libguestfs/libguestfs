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
# Test NBD support by attaching a guest via qemu-nbd and running inspection.

import os
import sys
import shutil
import time
import random
import atexit
import subprocess

import guestfs

prog = os.path.basename(sys.argv[0])

# Track the qemu-nbd process so we can clean it up on exit.
server_proc = None


def _cleanup_server() -> None:
    """Ensure any qemu-nbd process is terminated when the test exits."""
    global server_proc
    if server_proc is not None:
        try:
            server_proc.terminate()
            server_proc.wait(timeout=10)
        except Exception:
            # Last resort: kill -9 if terminate didn't work or timed out.
            try:
                server_proc.kill()
            except Exception:
                pass
        finally:
            server_proc = None


atexit.register(_cleanup_server)

# Allow skipping the test via environment variable (mirrors SKIP_TEST_NBD_PL).
if os.environ.get("SKIP_TEST_NBD_PY"):
    sys.exit(77)

# Check that qemu-nbd is available and callable.
try:
    result = subprocess.run(
        ["qemu-nbd", "--help"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        print(f"{prog}: test skipped because qemu-nbd program not found")
        sys.exit(77)
except FileNotFoundError:
    print(f"{prog}: test skipped because qemu-nbd program not found")
    sys.exit(77)

# Make a local copy of the disk so we can safely open it for writes.
disk = "../test-data/phony-guests/fedora.img"
if not os.path.isfile(disk) or os.path.getsize(disk) == 0:
    print(f"{prog}: test skipped because {disk} is not found")
    sys.exit(77)

local_disk = "fedora-nbd.img"
shutil.copyfile(disk, local_disk)
disk = local_disk

# Check if qemu-nbd supports the --format option (like the Perl grep).
has_format_opt = False
try:
    help_out = subprocess.run(
        ["qemu-nbd", "--help"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if help_out.returncode == 0 and "--format" in help_out.stdout:
        has_format_opt = True
except Exception:
    # If this check fails for some reason, just assume no --format option.
    has_format_opt = False


def run_test(readonly: bool, tcp: bool) -> None:
    """Run a single NBD test.

    :param readonly: If True, attach the NBD drive read-only.
    :param tcp: If True, connect using TCP; otherwise use Unix domain socket.
    """
    global server_proc

    cwd = os.getcwd()
    pidfile = os.path.join(cwd, "nbd", "nbd.pid")

    # Ensure the nbd/ directory exists so we can create pidfile and socket.
    os.makedirs(os.path.dirname(pidfile), exist_ok=True)

    # Base qemu-nbd command.
    qemu_nbd_cmd = [
        "qemu-nbd",
        disk,
        "-t",  # persistent, multiple connections allowed
        "--pid-file",
        pidfile,
    ]

    # Add '--format raw' if supported.
    if has_format_opt:
        qemu_nbd_cmd.extend(["--format", "raw"])

    socket_path = None

    if tcp:
        # Choose a random port number.  The original Perl test doesn't
        # check if it is already in use, so we don't either.
        port = random.randint(60000, 64999)
        qemu_nbd_cmd.extend(["-p", str(port)])
        server = f"localhost:{port}"
    else:
        # Unix domain socket: qemu-nbd insists on an absolute path.
        socket_path = os.path.join(cwd, "nbd", "unix.sock")
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
        qemu_nbd_cmd.extend(["-k", socket_path])
        server = f"unix:{socket_path}"

    print("Starting", " ".join(qemu_nbd_cmd), "...")
    # Start qemu-nbd in the background.
    server_proc = subprocess.Popen(qemu_nbd_cmd)

    # Wait for the pid file to appear, up to ~60 seconds (1s intervals).
    for _ in range(60):
        if os.path.isfile(pidfile):
            break
        # If qemu-nbd exited early, bail out immediately.
        if server_proc.poll() is not None:
            _cleanup_server()
            raise RuntimeError("qemu-nbd exited unexpectedly while starting")
        time.sleep(1)
    else:
        _cleanup_server()
        raise RuntimeError("qemu-nbd did not start up")

    # If using a Unix domain socket, try relabeling for SELinux.
    # Failure is not fatal (maybe SELinux is disabled).
    if socket_path is not None:
        try:
            subprocess.run(
                ["chcon", "-vt", "svirt_image_t", socket_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            # chcon not available, ignore.
            pass

    g = guestfs.GuestFS()

    try:
        # Add an NBD drive via protocol=nbd.
        # ``server`` expects a list; we pass the full "localhost:port" or "unix:/path".
        g.add_drive(
            "",
            readonly=bool(readonly),
            format="raw",
            protocol="nbd",
            server=[server],
        )

        # This fails if qemu can't connect to the NBD server.
        g.launch()

        # Inspection is a fairly thorough test of the guest.
        roots = g.inspect_os()
        if len(roots) != 1:
            raise RuntimeError("roots should be a 1-sized array")
        if roots[0] != "/dev/VG/Root":
            raise RuntimeError(f"{roots[0]} != /dev/VG/Root")

    finally:
        # Close guestfs handle (which will kill its qemu instance).
        try:
            g.close()
        except Exception:
            pass

        # Terminate qemu-nbd and wait for it.
        _cleanup_server()
        try:
            os.unlink(pidfile)
        except FileNotFoundError:
            pass


def main() -> int:
    # Since read-only and read-write paths are quite different,
    # test both via TCP.
    for readonly in (True, False):
        run_test(readonly, tcp=True)

    # Test Unix domain socket codepath (read-write).
    run_test(readonly=False, tcp=False)

    # Cleanup the copied disk image.
    try:
        os.unlink(disk)
    except FileNotFoundError:
        pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
