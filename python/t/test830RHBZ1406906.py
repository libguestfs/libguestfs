# libguestfs Python bindings
# Copyright (C) 2017 Red Hat Inc.
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

import os
import sys
import shutil
import tempfile
import unittest

import guestfs


class Test830RHBZ1406906(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tempdir)

    def test_rhbz1406906(self):
        g = guestfs.GuestFS(python_return_dict=True)

        g.add_drive_scratch(512 * 1024 * 1024)
        g.launch()

        g.part_disk("/dev/sda", "mbr")
        g.mkfs("ext4", "/dev/sda1")
        g.mount("/dev/sda1", "/")

        self.assertEqual(g.find("/"), ['lost+found'])

        # touch file with illegal unicode character
        non_utf8_fname = "\udcd4"
        open(os.path.join(self.tempdir, non_utf8_fname), "w").close()

        g.copy_in(self.tempdir, "/")

        if sys.version_info >= (3, 0):
            with self.assertRaises(UnicodeDecodeError):
                g.find("/")  # segfault here on Python 3
        elif sys.version_info >= (2, 0):
            self.assertTrue(
                any(path for path in g.find("/") if non_utf8_fname in path))
