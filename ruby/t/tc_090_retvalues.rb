# libguestfs Ruby bindings -*- ruby -*-
# Copyright (C) 2016 Red Hat Inc.
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

class Test090RetValues < MiniTest::Unit::TestCase
  def test_090_retvalues
    g = Guestfs::Guestfs.new()

    assert_equal 10, g.internal_test_rint("10")

    assert_raises(Guestfs::Error) {
      g.internal_test_rinterr()
    }
  end

  def test_rint64
    g = Guestfs::Guestfs.new()

    assert_equal 10, g.internal_test_rint64("10")

    assert_raises(Guestfs::Error) {
      g.internal_test_rint64err()
    }
  end

  def test_rbool
    g = Guestfs::Guestfs.new()

    assert_equal 1, g.internal_test_rbool("true")
    assert_equal 0, g.internal_test_rbool("false")

    assert_raises(Guestfs::Error) {
      g.internal_test_rboolerr()
    }
  end

  def test_rconststring
    g = Guestfs::Guestfs.new()

    assert_equal "static string", g.internal_test_rconststring("test")

    assert_raises(Guestfs::Error) {
      g.internal_test_rconststringerr()
    }
  end

  def test_rconstoptstring
    g = Guestfs::Guestfs.new()

    assert_equal "static string", g.internal_test_rconstoptstring("test")

    # this never fails
    assert_nil g.internal_test_rconstoptstringerr()
  end

  def test_rstring
    g = Guestfs::Guestfs.new()

    assert_equal "test", g.internal_test_rstring("test")

    assert_raises(Guestfs::Error) {
      g.internal_test_rstringerr()
    }
  end

  def test_rstringlist
    g = Guestfs::Guestfs.new()

    assert_equal [], g.internal_test_rstringlist("0")
    assert_equal ["0", "1", "2", "3", "4"], g.internal_test_rstringlist("5")

    assert_raises(Guestfs::Error) {
      g.internal_test_rstringlisterr()
    }
  end

  def test_rstruct
    g = Guestfs::Guestfs.new()

    s = g.internal_test_rstruct("unused")
    assert_instance_of Hash, s
    assert_equal "pv0", s["pv_name"]

    assert_raises(Guestfs::Error) {
      g.internal_test_rstructerr()
    }
  end

  def test_rstructlist
    g = Guestfs::Guestfs.new()

    assert_equal [], g.internal_test_rstructlist("0")
    l = g.internal_test_rstructlist("5")
    assert_instance_of Array, l
    assert_equal 5, l.length
    for i in 0..4
      assert_instance_of Hash, l[i]
      assert_equal "pv#{i}", l[i]["pv_name"]
    end

    assert_raises(Guestfs::Error) {
      g.internal_test_rstructlisterr()
    }
  end

  def test_rhashtable
    g = Guestfs::Guestfs.new()

    assert_equal Hash[], g.internal_test_rhashtable("0")
    assert_equal Hash["0"=>"0","1"=>"1","2"=>"2","3"=>"3","4"=>"4"], g.internal_test_rhashtable("5")

    assert_raises(Guestfs::Error) {
      g.internal_test_rhashtableerr()
    }
  end

  def test_rbufferout
    g = Guestfs::Guestfs.new()

    assert_equal "test", g.internal_test_rbufferout("test")

    assert_raises(Guestfs::Error) {
      g.internal_test_rbufferouterr()
    }
  end
end
