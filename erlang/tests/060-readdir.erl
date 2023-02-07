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

    Disk_image = "test-readdir.img",

    {ok, File} = file:open(Disk_image, [raw, write, binary]),
    {ok, _} = file:position(File, 10 * 1024 * 1024 - 1),
    ok = file:write(File, " "),
    ok = file:close(File),

    ok = guestfs:add_drive(G, Disk_image),
    ok = guestfs:launch(G),
    ok = guestfs:part_disk(G, "/dev/sda", "mbr"),
    ok = guestfs:mkfs(G, "ext2", "/dev/sda1"),
    ok = guestfs:mount(G, "/dev/sda1", "/"),
    ok = guestfs:mkdir(G, "/p"),
    ok = guestfs:mkdir(G, "/q"),

    Dirs = guestfs:readdir(G, "/"),
    [[_, $d, "."],
     [_, $d, ".."],
     [_, $d, "lost+found"],
     [_, $d, "p"],
     [_, $d, "q"]]
        = lists:sort(Dirs),

    ok = guestfs:shutdown(G),
    ok = guestfs:close(G),
    file:delete(Disk_image).
