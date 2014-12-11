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
import random
import string
import re
import os
import guestfs

try:
    import libvirt
except:
    print "skipping test: could not import python-libvirt"
    exit (77)

# If the backend is not libvirt, skip the test.
backend = guestfs.GuestFS().get_backend()
re = re.compile ("^libvirt")
if not re.match (backend):
    print "skipping test: backend is not libvirt"
    exit (77)

conn = libvirt.open (None)

# Check we're using the version of libvirt-python that has c_pointer() methods.
if not "c_pointer" in dir (conn):
    print "skipping test: libvirt-python doesn't support c_pointer()"
    exit (77)

# Create a test disk.
filename = os.getcwd () + "/820-rhbz912499.img"
guestfs.GuestFS().disk_create (filename, "raw", 1024*1024*1024)

# Create a new domain.  This won't work, it will just hang when
# booted.  But that's sufficient for the test.
domname = ''.join (random.choice (string.ascii_uppercase) for _ in range (8))
domname = "tmp-" + domname

xml = """
<domain type='kvm'>
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
""" % (domname, filename)

dom = conn.createXML (xml, libvirt.VIR_DOMAIN_START_AUTODESTROY)
if dom == None:
    raise "could not create temporary domain (%s)" % domname

print "temporary domain %s is running" % domname

# Libvirt should have labelled the disk.
print "before starting libguestfs"
before = check_output (["ls", "-Z", filename])
print "disk label = %s" % before

# Now see if we can open the domain with libguestfs without
# disturbing the label.
g = guestfs.GuestFS ()
r = g.add_libvirt_dom (dom, readonly = 1)
if r != 1:
    raise "unexpected return value from add_libvirt_dom (%d)" % r
g.launch ()

print "after starting libguestfs"
after = check_output (["ls", "-Z", filename])
print "disk label = %s" % after

if before != after:
    raise "disk label was changed unexpectedly"

os.unlink (filename)
