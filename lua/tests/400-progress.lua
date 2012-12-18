#!/bin/sh
# -*- lua -*-
test -z "$LUA" && LUA=lua
exec $LUA << END_OF_FILE
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

local G = require "guestfs"

local g = G.create ()

g:add_drive ("/dev/null")
g:launch ()

calls = 0
function cb ()
   calls = calls+1
end

eh = g:set_event_callback (cb, "progress")
assert (g:debug ("progress", {"5"}) == "ok", "debug progress command failed")
assert (calls > 0, "progress callback was not invoked")

calls = 0
g:delete_event_callback (eh)
assert (g:debug ("progress", {"5"}) == "ok", "debug progress command failed")
assert (calls == 0, "progress callback was invoked when deleted")

g:set_event_callback (cb, "progress")
assert (g:debug ("progress", {"5"}) == "ok", "debug progress command failed")
assert (calls > 0, "progress callback was not invoked")

g:close ()
