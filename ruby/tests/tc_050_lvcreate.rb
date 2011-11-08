# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2009 Red Hat Inc.
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

require 'test/unit'
$:.unshift(File::join(File::dirname(__FILE__), "..", "lib"))
$:.unshift(File::join(File::dirname(__FILE__), "..", "ext", "guestfs"))
require 'guestfs'

class TestLoad < Test::Unit::TestCase
  def test_lvcreate
    g = Guestfs::create()

    File.open("test.img", "w") {
      |f| f.seek(500*1024*1024); f.write("\0")
    }

    g.add_drive("test.img")
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

    File.unlink("test.img")
  end
end
