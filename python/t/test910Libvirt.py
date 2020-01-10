# libguestfs Python bindings
# Copyright (C) 2014 Red Hat Inc.
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

# The Python bindings for add_libvirt_dom require the libvirt-python
# library to support a new method (.c_pointer()).  Ensure this keeps
# working by testing it.  See:
# https://bugzilla.redhat.com/show_bug.cgi?id=1075164

import unittest
import os
import guestfs
from .tests_helper import *

guestsdir = os.environ['guestsdir']


@skipUnlessConfiguredWithLibvirt()
@skipUnlessLibvirtHasCPointer()
class Test910Libvirt(unittest.TestCase):
    def test_libvirt(self):
        import libvirt

        conn = libvirt.open("test:///%s/guests.xml" % guestsdir)
        dom = conn.lookupByName("blank-disk")

        g = guestfs.GuestFS()

        r = g.add_libvirt_dom(dom, readonly=1)
        self.assertEqual(r, 1)
