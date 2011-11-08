# libguestfs Python bindings
# Copyright (C) 2011 Red Hat Inc.
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

# Test implicit vs explicit closes of the handle (RHBZ#717786).

import os
import guestfs

g = guestfs.GuestFS ()

g.close ()                      # explicit close
del g                           # implicit close - should be no error/warning

# Expect an exception if we call a method on a closed handle.
g = guestfs.GuestFS ()
g.close ()
try:
    g.set_memsize (512)
    raise Exception("expected an exception from previous statement")
except guestfs.ClosedHandle:
    pass
del g

# Verify that the handle is really being closed by g.close, by setting
# up a close event and testing that it happened.
g = guestfs.GuestFS ()

close_invoked = 0

def close_callback (ev, eh, buf, array):
    global close_invoked
    close_invoked += 1

g.set_event_callback (close_callback, guestfs.EVENT_CLOSE)

if close_invoked != 0:
    raise Exception("close_invoked should be 0")

g.close ()
if close_invoked != 1:
    raise Exception("close_invoked should be 1")

del g
if close_invoked != 1:
    raise Exception("close_invoked should be 1")
