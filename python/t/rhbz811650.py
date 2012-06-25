# libguestfs Python bindings
# Copyright (C) 2012 Red Hat Inc.
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
import guestfs

f = open ("test.img", "w")
f.truncate (500 * 1024 * 1024)
f.close ()

g = guestfs.GuestFS ()

# Deliberate error: the disk format is supposed to be raw.
g.add_drive_opts ("test.img", format="qcow2");

# Because error() wasn't being called, guestfs_last_error would return
# NULL, causing a segfault in the Python bindings (RHBZ#811650).
try:
    g.launch ()
except:
    pass

os.unlink ("test.img")
