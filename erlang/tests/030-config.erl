#!/usr/bin/env escript
%! -smp enable -sname test debug verbose

% libguestfs Erlang tests -*- erlang -*-
% Copyright (C) 2009-2023 Red Hat Inc.
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License along
% with this program; if not, write to the Free Software Foundation, Inc.,
% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

main(_) ->
    {ok, G} = guestfs:create(),

    ok = guestfs:set_verbose(G, true),
    true = guestfs:get_verbose(G),
    ok = guestfs:set_verbose(G, false),
    false = guestfs:get_verbose(G),

    ok = guestfs:set_autosync(G, true),
    true = guestfs:get_autosync(G),
    ok = guestfs:set_autosync(G, false),
    false = guestfs:get_autosync(G),

    ok = guestfs:set_path(G, "."),
    "." = guestfs:get_path(G),
    ok = guestfs:set_path(G, undefined),
    "" /= guestfs:get_path(G),

    ok = guestfs:add_drive(G, "/dev/null"),

    ok = guestfs:close(G).
