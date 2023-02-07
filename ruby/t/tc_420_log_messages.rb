# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2011-2023 Red Hat Inc.
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

require File::join(File::dirname(__FILE__), 'test_helper')

class Test420LogMessages < MiniTest::Unit::TestCase
  def test_420_log_messages
    g = Guestfs::Guestfs.new()

    log_invoked = 0
    log = Proc.new {| event, event_handle, buf, array |
      log_invoked += 1
      if event == Guestfs::EVENT_APPLIANCE
        buf.chomp!
      end
      event_string = Guestfs::event_to_string(event)
      puts "ruby event logged: event=#{event_string} eh=#{event_handle} buf='#{buf}' array=#{array}"
    }

    # Grab log, trace and daemon messages into our custom callback.
    event_bitmask = Guestfs::EVENT_APPLIANCE | Guestfs::EVENT_LIBRARY |
      Guestfs::EVENT_WARNING | Guestfs::EVENT_TRACE
    g.set_event_callback(log, event_bitmask)

    # Make sure we see some messages.
    g.set_trace(1)
    g.set_verbose(1)

    # Do some stuff.
    g.add_drive_ro("/dev/null")
    g.set_autosync(1)

    g.close()
    refute_equal 0, log_invoked
  end
end
