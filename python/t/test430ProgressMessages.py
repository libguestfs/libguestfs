# libguestfs Python bindings
# Copyright (C) 2019 Red Hat Inc.
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

import unittest
import guestfs

callback_invoked = 0


def callback(ev, eh, buf, array):
    global callback_invoked
    callback_invoked += 1


class Test430ProgressMessages(unittest.TestCase):
    def test_progress_messages(self):
        global callback_invoked
        g = guestfs.GuestFS(python_return_dict=True)
        g.add_drive('/dev/null')
        g.launch()

        events = guestfs.EVENT_PROGRESS

        eh = g.set_event_callback(callback, events)
        g.debug('progress', ['5'])
        self.assertTrue(callback_invoked > 0)

        callback_invoked = 0
        g.delete_event_callback(eh)
        g.debug('progress', ['5'])
        self.assertEqual(callback_invoked, 0)

        g.set_event_callback(callback, events)
        g.debug('progress', ['5'])
        self.assertTrue(callback_invoked > 0)

        g.close()
