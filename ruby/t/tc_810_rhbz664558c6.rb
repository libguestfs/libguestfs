# libguestfs Ruby bindings -*- ruby -*-
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

# Test that throwing an exception in a callback doesn't cause
# the interpreter to segfault.  See:
# https://bugzilla.redhat.com/show_bug.cgi?id=664558#c6

require 'test/unit'
$:.unshift(File::join(File::dirname(__FILE__), "..", "lib"))
$:.unshift(File::join(File::dirname(__FILE__), "..", "ext", "guestfs"))
require 'guestfs'

class TestLoad < Test::Unit::TestCase
  def test_rhbz664558c6
    g = Guestfs::create()

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

    if close_invoked != 1
      raise "close_invoked should be 1"
    end
  end
end
