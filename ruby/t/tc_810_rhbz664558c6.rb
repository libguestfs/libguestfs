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

# Test that throwing an exception in a callback doesn't cause
# the interpreter to segfault.  See:
# https://bugzilla.redhat.com/show_bug.cgi?id=664558#c6

require File::join(File::dirname(__FILE__), 'test_helper')

class Test810RHBZ664558C6 < MiniTest::Unit::TestCase
  def test_810_rhbz_664558c6
    g = Guestfs::Guestfs.new()

    close_invoked = 0
    close = Proc.new {| event, event_handle, buf, array |
      close_invoked += 1
      # Raising an exception used to cause the interpreter to
      # segfault.  It should just cause an error message to be
      # printed on stderr.
      raise "ignore this error"
    }
    g.set_event_callback(close, Guestfs::EVENT_CLOSE)

    # This should call the close callback.
    g.close()

    assert_equal 1, close_invoked
  end
end
