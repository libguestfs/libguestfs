# libguestfs Python bindings
# Copyright (C) 2026 Red Hat Inc.
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

# Test string list handling in C bindings, especially Unicode strings
# passed through guestfs_int_py_asstring / guestfs_int_py_get_string_list.

import unittest
import guestfs


class Test060StringList(unittest.TestCase):
    def setUp(self):
        self.g = guestfs.GuestFS()

    def test_ascii_string_list(self):
        """Pass ASCII string list to internal_test."""
        self.g.internal_test("str", None, ["a", "b", "c"],
                             False, 0, 0, "/dev/null", "/dev/null",
                             b"buf")

    def test_unicode_string_list(self):
        """Pass Unicode string list to exercise PyUnicode_AsUTF8."""
        self.g.internal_test("str", None,
                             ["\u00e9", "\u00f1", "\u00fc", "\u2603"],
                             False, 0, 0, "/dev/null", "/dev/null",
                             b"buf")

    def test_empty_string_list(self):
        """Pass empty string list."""
        self.g.internal_test("str", None, [],
                             False, 0, 0, "/dev/null", "/dev/null",
                             b"buf")

    def test_large_string_list(self):
        """Pass a large string list to check for reference leaks."""
        big_list = ["string_%d" % i for i in range(1000)]
        self.g.internal_test("str", None, big_list,
                             False, 0, 0, "/dev/null", "/dev/null",
                             b"buf")

    def test_unicode_opt_string_list(self):
        """Pass Unicode strings via optional string list arg."""
        self.g.internal_test("str", None, [],
                             False, 0, 0, "/dev/null", "/dev/null",
                             b"buf",
                             ostringlist=["\u00e9", "\u00f1", "\u00fc"])

    def tearDown(self):
        self.g.close()
