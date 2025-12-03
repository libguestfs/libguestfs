#!/usr/bin/env python3
# Copyright (C) 2025 Red Hat Inc.
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

# Test that console debug messages work.

import os
import sys
import guestfs

if os.environ.get('SKIP_TEST_CONSOLE_DEBUG_PY'):
    sys.exit(77)

g = guestfs.GuestFS()

log_messages = ""
callback_invoked = 0

def callback(ev, eh, buf, array):
    global log_messages, callback_invoked

    # guestfs passes log buffer as bytes under Python 3, so decode first
    if isinstance(buf, bytes):
        buf = buf.decode("utf-8", errors="replace")

    log_messages += buf
    callback_invoked += 1

events = guestfs.EVENT_APPLIANCE
eh = g.set_event_callback(callback, events)

g.set_verbose(1)
g.add_drive_ro("/dev/null")
g.launch()

magic = "abcdefgh9876543210"
g.debug("print", [magic])

g.close()

# Ensure the magic string appeared in the log messages.
if magic not in log_messages:
    print("log_messages does not contain magic string '{}'".format(magic))
    print("callback was invoked {} times".format(callback_invoked))
    print("log messages were:")
    print("-" * 40)
    print(log_messages)
    print("-" * 40)
    sys.exit(1)
