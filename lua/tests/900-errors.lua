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

code, err = pcall (function (fn) g:add_drive (fn) end, "/NOTSUCHFILE")
assert (not code)

-- The default __tostring function will convert the error to either:
--
--   "%s", msg
-- or:
--   "%s: %s", msg, strerror (err)
--
-- We are expecting the second case here, but since the libguestfs
-- code calls perrorf, the string version of ENOENT is already
-- included in 'msg' and so appears twice here.
local str = tostring (err)
assert (str == "/NOTSUCHFILE: No such file or directory: No such file or directory",
        string.format ("unexpected error string: %s", str))
