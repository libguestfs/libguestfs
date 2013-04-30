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
import os
import guestfs

g = guestfs.GuestFS (python_return_dict=False)

r = g.internal_test_rhashtable ("5")
if type(r) != list or r != [ ("0","0"), ("1","1"), ("2","2"), ("3","3"), ("4","4") ]:
    raise Exception ("python_return_dict=False: internal_test_rhashtable returned %s" % r)

g = guestfs.GuestFS (python_return_dict=True)

r = g.internal_test_rhashtable ("5")
if type(r) != dict or sorted (r.keys()) != ["0","1","2","3","4"] or r["0"] != "0" or r["1"] != "1" or r["2"] != "2" or r["3"] != "3" or r["4"] != "4":
    raise Exception ("python_return_dict=True: internal_test_rhashtable returned %s" % r)
