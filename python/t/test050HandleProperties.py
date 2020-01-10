# libguestfs Python bindings
# Copyright (C) 2019 Red Hat Inc.
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

import unittest
import warnings
import guestfs


class Test050HandleProperties(unittest.TestCase):
    def test_verbose(self):
        g = guestfs.GuestFS(python_return_dict=True)
        g.set_verbose(1)
        self.assertEqual(g.get_verbose(), 1)
        g.set_verbose(0)
        self.assertEqual(g.get_verbose(), 0)

    def test_autosync(self):
        g = guestfs.GuestFS(python_return_dict=True)
        g.set_autosync(1)
        self.assertEqual(g.get_autosync(), 1)
        g.set_autosync(0)
        self.assertEqual(g.get_autosync(), 0)

    def test_path(self):
        g = guestfs.GuestFS(python_return_dict=True)
        g.set_path(".")
        self.assertEqual(g.get_path(), ".")

    def test_add_drive(self):
        g = guestfs.GuestFS(python_return_dict=True)
        g.add_drive("/dev/null")

    def test_add_cdrom(self):
        g = guestfs.GuestFS(python_return_dict=True)
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=DeprecationWarning)
            g.add_cdrom("/dev/zero")
