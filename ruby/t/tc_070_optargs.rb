# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2010-2025 Red Hat Inc.
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

require 'minitest/autorun'
require 'guestfs'

class Test070Optargs < Minitest::Test
  def test_070_optargs
    g = Guestfs::Guestfs.new()

    g.add_drive("/dev/null", {})
    g.add_drive("/dev/null", :readonly => true)
    g.add_drive("/dev/null", :readonly => true, :iface => "virtio")
    g.add_drive("/dev/null",
                :readonly => true, :iface => "virtio", :format => "raw")
  end
end
