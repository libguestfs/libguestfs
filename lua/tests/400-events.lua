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

for i, v in ipairs (G.event_all) do
   print (i, v)
end

local g = G.create ()

function log_callback (g, event, eh, flags, buf, array)
   io.write (string.format ("lua event logged: event=%s eh=%d buf='%s'\n",
                            event, eh, buf))
end

close_invoked = 0
function close_callback (g, event, eh, flags, buf, array)
   close_invoked = close_invoked+1
   log_callback (g, event, eh, flags, buf, array)
end

-- Register an event callback for all log messages.
g:set_event_callback (log_callback, { "appliance", "library", "trace" })

-- Register an event callback for the close event.
g:set_event_callback (close_callback, "close")

-- Make sure we see some messages.
g:set_trace (true)
g:set_verbose (true)

-- Do some stuff.
g:add_drive_ro ("/dev/null")

-- Close the handle.  The close callback should be invoked.
g:close ()
assert (close_invoked == 1, "close callback was not invoked")
