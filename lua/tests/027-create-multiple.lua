#!/usr/bin/lua
-- libguestfs Lua bindings -*- lua -*-
-- Copyright (C) 2012 Red Hat Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require "guestfs"

g1 = Guestfs.create ()
g2 = Guestfs.create ()
g3 = Guestfs.create ()

-- Check that each handle is independent.
g1:set_path ("1")
g2:set_path ("2")
g3:set_path ("3")

if g1:get_path () ~= "1" then
   error (string.format ("incorrect path in g1, expected '1', got '%s'",
                         g1:get_path ()))
end
if g2:get_path () ~= "2" then
   error (string.format ("incorrect path in g2, expected '2', got '%s'",
                         g2:get_path ()))
end
if g3:get_path () ~= "3" then
   error (string.format ("incorrect path in g3, expected '3', got '%s'",
                         g3:get_path ()))
end
