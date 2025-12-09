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
# Test NBD support by attaching a guest via nbdkit and running inspection.
#
# Historically this test used qemu-nbd over TCP.  Nowadays nbdkit plus Unix
# domain sockets is available, so we use that instead.

import os
import sys
import shutil
import time
import atexit
import subprocess

import guestfs

prog = os.path.basename(sys.argv[0])

# Track the nbdkit process so we can clean it up on exit.
server_proc = None


def _cleanup_server() -> None:
    """Ensure any nbdkit process is terminated when the test exits."""
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

# Allow skipping the test via environment variable
# (mirrors SKIP_TEST_NBD_PL / SKIP_TEST_NBD_PY style).
if os.environ.get("SKIP_TEST_NBD_PY"):
    sys.exit(77)

# Check that nbdkit is available and callable.
try:
    result = subprocess.run(
        ["nbdkit", "--version"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        print(f"{prog}: test skipped because nbdkit program not found")
        sys.exit(77)
except FileNotFoundError:
    print(f"{prog}: test skipped because nbdkit program not found")
    sys.exit(77)

# Make a local copy of the disk so we can safely open it for writes.
disk = "../test-data/phony-guests/fedora.img"
if not os.path.isfile(disk) or os.path.getsize(disk) == 0:
    print(f"{prog}: test skipped because {disk} is not found")
    sys.exit(77)

local_disk = "fedora-nbd.img"
shutil.copyfile(disk, local_disk)
disk = local_disk


def run_test(readonly: bool) -> None:
    """Run a single NBD test using nbdkit over a Unix domain socket.

    :param readonly: If True, start nbdkit read-only.
    """
    global server_proc

    cwd = os.getcwd()
    nbd_dir = os.path.join(cwd, "nbd")
    pidfile = os.path.join(nbd_dir, "nbdkit.pid")
    socket_path = os.path.join(nbd_dir, "nbdkit.sock")

    # Ensure the nbd/ directory exists so we can create pidfile and socket.
    os.makedirs(nbd_dir, exist_ok=True)

    # Clean up any stale artifacts.
    for path in (pidfile, socket_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Base nbdkit command:
    #
    #   -U <unix-socket>    listen on a Unix domain socket at this path
    #   -f                  stay in the foreground (so Popen tracks the process)
    #   -P <pidfile>        write a pidfile when ready to serve
    #
    # We use the file plugin to serve the local disk copy.
    nbdkit_cmd = [
        "nbdkit",
        "-U",
        socket_path,
        "-f",
        "-P",
        pidfile,
    ]

    # For the read-only variant, add -r (read-only export).
    if readonly:
        nbdkit_cmd.append("-r")

    # Plugin and its arguments.
    # This is "file DISK" – no extra options needed.
    nbdkit_cmd.extend(["file", disk])

    print("Starting", " ".join(nbdkit_cmd), "...")
    server_proc = subprocess.Popen(nbdkit_cmd)

    # Wait for the pid file to appear, up to ~60 seconds (1s intervals).
    for _ in range(60):
        if os.path.isfile(pidfile):
            break
        # If nbdkit exited early, bail out immediately.
        if server_proc.poll() is not None:
            _cleanup_server()
            raise RuntimeError("nbdkit exited unexpectedly while starting")
        time.sleep(1)
    else:
        _cleanup_server()
        raise RuntimeError("nbdkit did not start up")

    # Try relabeling the socket for SELinux. Failure is not fatal.
    try:
        subprocess.run(
            ["chcon", "-vt", "svirt_image_t", socket_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        # chcon not available, ignore.
        pass

    # Now connect via libguestfs using protocol=nbd and unix: socket.
    g = guestfs.GuestFS()

    server = f"unix:{socket_path}"

    try:
        g.add_drive(
            "",
            readonly=bool(readonly),
            format="raw",
            protocol="nbd",
            server=[server],
        )

        # This fails if libguestfs/qemu can't connect to the NBD server.
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

        # Terminate nbdkit and wait for it.
        _cleanup_server()

        # Clean up socket and pidfile if they still exist.
        for path in (pidfile, socket_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def main() -> int:
    # Since read-only and read-write paths are quite different,
    # test both using the Unix socket transport.
    for readonly in (True, False):
        run_test(readonly)

    # Cleanup the copied disk image.
    try:
        os.unlink(disk)
    except FileNotFoundError:
        pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
