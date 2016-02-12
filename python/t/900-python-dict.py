# libguestfs Python bindings
# Copyright (C) 2013 Red Hat Inc.
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

# Test python-specific python_return_dict parameter.

from types import *
import unittest
import os
import guestfs

class Test900PythonDict (unittest.TestCase):
    def test_python_no_dict (self):
        g = guestfs.GuestFS (python_return_dict=False)

        r = g.internal_test_rhashtable ("5")
        self.assertTrue (isinstance (r, list))
        self.assertEqual (r, [ ("0","0"), ("1","1"), ("2","2"),
                               ("3","3"), ("4","4") ])

    def test_python_dict (self):
        g = guestfs.GuestFS (python_return_dict=True)

        r = g.internal_test_rhashtable ("5")
        self.assertTrue (isinstance (r, dict))
        self.assertEqual (sorted (r.keys()), ["0","1","2","3","4"])
        self.assertEqual (r["0"], "0")
        self.assertEqual (r["1"], "1")
        self.assertEqual (r["2"], "2")
        self.assertEqual (r["3"], "3")
        self.assertEqual (r["4"], "4")

if __name__ == '__main__':
    unittest.main ()
