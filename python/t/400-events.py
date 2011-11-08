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

import os
import guestfs

g = guestfs.GuestFS()

def log_callback (ev,eh,buf,array):
    if ev == guestfs.EVENT_APPLIANCE:
        buf = buf.rstrip()

    # Log what happened.
    print ("python event logged: event=0x%x eh=%d buf='%s' array=%s" %
           (ev, eh, buf, array))

close_invoked = 0

def close_callback (ev, eh, buf, array):
    global close_invoked
    close_invoked += 1
    log_callback (ev, eh, buf, array)

# Register an event callback for all log messages.
events = guestfs.EVENT_APPLIANCE | guestfs.EVENT_LIBRARY | guestfs.EVENT_TRACE
g.set_event_callback (log_callback, events)

# Register a callback for the close event.
g.set_event_callback (close_callback, guestfs.EVENT_CLOSE)

# Now make sure we see some messages.
g.set_trace (1)
g.set_verbose (1)

# Do some stuff.
g.add_drive_ro ("/dev/null")
g.set_autosync (1)

# Close the handle.  The close callback should be invoked.
if close_invoked != 0:
    raise "Error: close_invoked should be 0"
del g
if close_invoked != 1:
    raise "Error: close_invoked should be 1"
