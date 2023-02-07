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

# Test that we don't break the old ::create module function while
# fixing https://bugzilla.redhat.com/show_bug.cgi?id=1046509

require File::join(File::dirname(__FILE__), 'test_helper')

class Test820RHBZ1046509 < MiniTest::Unit::TestCase
  def _handleok(g)
    g.add_drive("/dev/null")
    g.close()
  end

  def test_820_rhbz1046509
    g = Guestfs::create()
    _handleok(g)

    g = Guestfs::create(:close_on_exit => true)
    _handleok(g)

    g = Guestfs::create(:close_on_exit => true, :environment => true)
    _handleok(g)
  end
end
