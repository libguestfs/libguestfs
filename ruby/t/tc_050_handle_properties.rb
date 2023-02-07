# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2013-2023 Red Hat Inc.
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

class Test050HandleProperties < MiniTest::Unit::TestCase
  def test_050_handle_properties
    g = Guestfs::Guestfs.new()
    refute_nil (g)
    v = g.get_verbose()
    g.set_verbose(v)
    v = g.get_trace()
    g.set_trace(v)
    v = g.get_memsize()
    g.set_memsize(v)
    v = g.get_path()
    g.set_path(v)
  end
end
