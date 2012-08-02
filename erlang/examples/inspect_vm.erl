#!/usr/bin/env escript
%%! -smp enable -sname inspect_vm debug verbose
% Example showing how to inspect a virtual machine disk.

main([Disk]) ->
    {ok, G} = guestfs:create(),

    % Attach the disk image read-only to libguestfs.
    ok = guestfs:add_drive_opts(G, Disk, [{readonly, true}]),

    % Run the libguestfs back-end.
    ok = guestfs:launch(G),

    % Ask libguestfs to inspect for operating systems.
    case guestfs:inspect_os(G) of
        [] ->
            io:fwrite("inspect_vm: no operating systems found~n"),
            exit(no_operating_system);
        Roots ->
            list_os(G, Roots)
    end.

list_os(_, []) ->
    ok;
list_os(G, [Root|Roots]) ->
    io:fwrite("Root device: ~s~n", [Root]),

    % Print basic information about the operating system.
    Product_name = guestfs:inspect_get_product_name(G, Root),
    io:fwrite("  Product name: ~s~n", [Product_name]),
    Major = guestfs:inspect_get_major_version(G, Root),
    Minor = guestfs:inspect_get_minor_version(G, Root),
    io:fwrite("  Version:      ~w.~w~n", [Major, Minor]),
    Type = guestfs:inspect_get_type(G, Root),
    io:fwrite("  Type:         ~s~n", [Type]),
    Distro = guestfs:inspect_get_distro(G, Root),
    io:fwrite("  Distro:       ~s~n", [Distro]),

    % Mount up the disks, like guestfish -i.
    Mps = sort_mps(guestfs:inspect_get_mountpoints(G, Root)),
    mount_mps(G, Mps),

    % If /etc/issue.net file exists, print up to 3 lines. *)
    Filename = "/etc/issue.net",
    Is_file = guestfs:is_file(G, Filename),
    if Is_file ->
            io:fwrite("--- ~s ---~n", [Filename]),
            Lines = guestfs:head_n(G, 3, Filename),
            write_lines(Lines);
       true -> ok
    end,

    % Unmount everything.
    ok = guestfs:umount_all(G),

    list_os(G, Roots).

% Sort keys by length, shortest first, so that we end up
% mounting the filesystems in the correct order.
sort_mps(Mps) ->
    Cmp = fun ({A,_}, {B,_}) ->
                  length(A) =< length(B) end,
    lists:sort(Cmp, Mps).

mount_mps(_, []) ->
    ok;
mount_mps(G, [{Mp, Dev}|Mps]) ->
    case guestfs:mount_ro(G, Dev, Mp) of
        ok -> ok;
        { error, Msg, _ } ->
            io:fwrite("~s (ignored)~n", [Msg])
    end,
    mount_mps(G, Mps).

write_lines([]) ->
    ok;
write_lines([Line|Lines]) ->
    io:fwrite("~s~n", [Line]),
    write_lines(Lines).
