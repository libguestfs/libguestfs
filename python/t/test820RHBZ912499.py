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

# Test that SELinux relabelling code doesn't regress.
# See: https://bugzilla.redhat.com/912499#c10
#      https://bugzilla.redhat.com/1075164#c7

from subprocess import check_output
import unittest
import random
import string
import os
import guestfs
from .tests_helper import *


# If the architecture doesn't support IDE, skip the test.
@skipIfEnvironmentVariableSet("SKIP_TEST820RHBZ912499_PY")
@skipUnlessArchMatches("(i.86|x86_64)")
@skipUnlessGuestfsBackendIs('libvirt')
@skipUnlessLibvirtHasCPointer()
class Test820RHBZ912499(unittest.TestCase):
    def setUp(self):
        # Create a test disk.
        self.filename = os.getcwd() + "/820-rhbz912499.img"
        guestfs.GuestFS().disk_create(self.filename, "raw", 1024 * 1024 * 1024)

        # Create a new domain.  This won't work, it will just hang when
        # booted.  But that's sufficient for the test.
        self.domname = ''.join(random.choice(string.ascii_uppercase)
                               for _ in range(8))
        self.domname = "tmp-" + self.domname

        self.xml = """
<domain type='qemu'>
  <name>%s</name>
  <memory>1048576</memory>
  <vcpu>1</vcpu>
  <os>
    <type>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='%s'/>
      <target dev='hda' bus='ide'/>
    </disk>
  </devices>
</domain>
""" % (self.domname, self.filename)

    def test_rhbz912499(self):
        import libvirt

        conn = libvirt.open(None)
        dom = conn.createXML(self.xml,
                             libvirt.VIR_DOMAIN_START_AUTODESTROY)
        self.assertIsNotNone(dom)

        print("temporary domain %s is running" % self.domname)

        # Libvirt should have labelled the disk.
        print("before starting libguestfs")
        before = check_output(["ls", "-Z", self.filename])
        print("disk label = %s" % before)

        # Now see if we can open the domain with libguestfs without
        # disturbing the label.
        g = guestfs.GuestFS()
        r = g.add_libvirt_dom(dom, readonly=1)
        self.assertEqual(r, 1)
        g.launch()

        print("after starting libguestfs")
        after = check_output(["ls", "-Z", self.filename])
        print("disk label = %s" % after)

        self.assertEqual(before, after)

    def tearDown(self):
        os.unlink(self.filename)
