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

# Test logic for setting location of tmpdir and cachedir.

import sys
import os
import guestfs
import tempfile

# Remove any environment variables that may have been set by the
# user or the ./run script which could affect this test.
os.environ.pop('LIBGUESTFS_TMPDIR', None)
os.environ.pop('LIBGUESTFS_CACHEDIR', None)
os.environ.pop('TMPDIR', None)

# Defaults with no environment variables set.
g = guestfs.GuestFS()
assert g.get_tmpdir() == "/tmp"
assert g.get_cachedir() == "/var/tmp"

# Create some test directories.
with tempfile.TemporaryDirectory() as a, \
     tempfile.TemporaryDirectory() as b, \
     tempfile.TemporaryDirectory() as c:

    # Setting environment variables.
    os.environ['LIBGUESTFS_TMPDIR'] = a
    os.environ['LIBGUESTFS_CACHEDIR'] = b
    os.environ['TMPDIR'] = c

    g = guestfs.GuestFS()
    assert g.get_tmpdir() == a
    assert g.get_cachedir() == b

    # Creating a handle which isn't affected by environment variables.
    g = guestfs.GuestFS(environment=False)
    assert g.get_tmpdir() == "/tmp"
    assert g.get_cachedir() == "/var/tmp"

    # Uses TMPDIR if the others are not set.
    os.environ.pop('LIBGUESTFS_TMPDIR', None)
    g = guestfs.GuestFS()
    assert g.get_tmpdir() == c
    assert g.get_cachedir() == b

    os.environ.pop('LIBGUESTFS_CACHEDIR', None)
    g = guestfs.GuestFS()
    assert g.get_tmpdir() == c
    assert g.get_cachedir() == c

# Directories should be made absolute automatically.
os.environ.pop('LIBGUESTFS_TMPDIR', None)
os.environ.pop('LIBGUESTFS_CACHEDIR', None)
os.environ.pop('TMPDIR', None)
os.environ['TMPDIR'] = "."
g = guestfs.GuestFS()
pwd = os.getcwd()
assert g.get_tmpdir() == pwd
assert g.get_cachedir() == pwd
