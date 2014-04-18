# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2011-2014 Red Hat Inc.
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

class TestLoad < MiniTest::Unit::TestCase
  def test_events
    g = Guestfs::Guestfs.new()

    close_invoked = 0
    close = Proc.new {| event, event_handle, buf, array |
      close_invoked += 1
    }

    # Check that the close event is called.
    g.set_event_callback(close, Guestfs::EVENT_CLOSE)

    if close_invoked != 0
      raise "close_invoked should be 0"
    end
    g.close()
    if close_invoked != 1
      raise "close_invoked should be 1"
    end
  end
end
