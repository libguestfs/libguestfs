# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2009-2023 Red Hat Inc.
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

class Test800RHBZ507346 < MiniTest::Unit::TestCase
  def test_800_rhbz507346
    g = Guestfs::Guestfs.new()
    exception = assert_raises TypeError do
      g.parse_environment_list(1)
    end
    assert_match(/wrong argument type .* \(expected Array\)/,
                 exception.message)
  end
end
