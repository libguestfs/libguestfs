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

local verbose = g:get_verbose ()
g:set_verbose (true)
g:set_verbose (verbose)

g:set_autosync (false)
g:set_autosync (true)

g:set_path (".")
assert (g:get_path () == ".")

g:add_drive ("/dev/null")

local version = g:version ()
for k,v in pairs (version) do
   print(k,v)
end

g:close ()
