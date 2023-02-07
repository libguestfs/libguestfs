# libguestfs Python bindings
# Copyright (C) 2013-2023 Red Hat Inc.
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

# Test all the different return values.

import unittest
import guestfs
from .tests_helper import *


class Test090PythonRetValues(unittest.TestCase):
    def test_rint(self):
        g = guestfs.GuestFS()

        self.assertAlmostEqual(g.internal_test_rint("10"), 10, places=1)

        self.assertRaises(RuntimeError, g.internal_test_rinterr)

    def test_rint64(self):
        g = guestfs.GuestFS()

        self.assertAlmostEqual(g.internal_test_rint64("10"),
                               int_type(10), places=1)

        self.assertRaises(RuntimeError, g.internal_test_rint64err)

    def test_rbool(self):
        g = guestfs.GuestFS()

        self.assertTrue(g.internal_test_rbool("true"))
        self.assertFalse(g.internal_test_rbool("false"))

        self.assertRaises(RuntimeError, g.internal_test_rboolerr)

    def test_rconststring(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rconststring("test"), "static string")

        self.assertRaises(RuntimeError, g.internal_test_rconststringerr)

    def test_rconstoptstring(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rconstoptstring("test"),
                         "static string")

        # this never fails
        self.assertIsNone(g.internal_test_rconstoptstringerr())

    def test_rstring(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rstring("test"), "test")

        self.assertRaises(RuntimeError, g.internal_test_rstringerr)

    def test_rstringlist(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rstringlist("0"), [])
        self.assertEqual(g.internal_test_rstringlist("5"),
                         ["0", "1", "2", "3", "4"])

        self.assertRaises(RuntimeError, g.internal_test_rstringlisterr)

    def test_rstruct(self):
        g = guestfs.GuestFS()

        s = g.internal_test_rstruct("unused")
        self.assertIsInstance(s, dict)
        self.assertEqual(s["pv_name"], "pv0")

        self.assertRaises(RuntimeError, g.internal_test_rstructerr)

    def test_rstructlist(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rstructlist("0"), [])
        retlist = g.internal_test_rstructlist("5")
        self.assertIsInstance(retlist, list)
        self.assertEqual(len(retlist), 5)
        for i in range(0, 5):
            self.assertIsInstance(retlist[i], dict)
            self.assertEqual(retlist[i]["pv_name"], "pv%d" % i)

        self.assertRaises(RuntimeError, g.internal_test_rstructlisterr)

    def test_rhashtable_list(self):
        g = guestfs.GuestFS(python_return_dict=False)

        self.assertEqual(g.internal_test_rhashtable("0"), [])
        r = g.internal_test_rhashtable("5")
        self.assertEqual(r, [("0", "0"), ("1", "1"), ("2", "2"),
                             ("3", "3"), ("4", "4")])

        self.assertRaises(RuntimeError, g.internal_test_rhashtableerr)

    def test_rhashtable_dict(self):
        g = guestfs.GuestFS(python_return_dict=True)

        self.assertEqual(g.internal_test_rhashtable("0"), {})
        r = g.internal_test_rhashtable("5")
        self.assertEqual(r, {"0": "0", "1": "1", "2": "2", "3": "3", "4": "4"})

        self.assertRaises(RuntimeError, g.internal_test_rhashtableerr)

    def test_rbufferout(self):
        g = guestfs.GuestFS()

        self.assertEqual(g.internal_test_rbufferout("test"), b'test')

        self.assertRaises(RuntimeError, g.internal_test_rbufferouterr)
