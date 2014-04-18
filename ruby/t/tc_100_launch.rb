# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2009-2014 Red Hat Inc.
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
  def test_launch
    g = Guestfs::Guestfs.new()

    g.add_drive_scratch(500*1024*1024)
    g.launch()

    g.pvcreate("/dev/sda")
    g.vgcreate("VG", ["/dev/sda"]);
    g.lvcreate("LV1", "VG", 200);
    g.lvcreate("LV2", "VG", 200);

    lvs = g.lvs()
    if lvs != ["/dev/VG/LV1", "/dev/VG/LV2"]
      raise "incorrect lvs returned"
    end

    g.sync()
  end
end
