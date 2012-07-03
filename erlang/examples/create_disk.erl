#!/usr/bin/env escript
%%! -smp enable -sname create_disk debug verbose
% Example showing how to create a disk image.

main(_) ->
    Output = "disk.img",

    {ok, G} = guestfs:create(),

    % Create a raw-format sparse disk image, 512 MB in size.
    {ok, File} = file:open(Output, [raw, write, binary]),
    {ok, _} = file:position(File, 512 * 1024 * 1024 - 1),
    ok = file:write(File, " "),
    ok = file:close(File),

    % Set the trace flag so that we can see each libguestfs call.
    ok = guestfs:set_trace(G, true),

    % Attach the disk image to libguestfs.
    ok = guestfs:add_drive_opts(G, Output,
                                [{format, "raw"}, {readonly, false}]),

    % Run the libguestfs back-end.
    ok = guestfs:launch(G),

    % Get the list of devices.  Because we only added one drive
    % above, we expect that this list should contain a single
    % element.
    [Device] = guestfs:list_devices(G),

    % Partition the disk as one single MBR partition.
    ok = guestfs:part_disk(G, Device, "mbr"),

    % Get the list of partitions.  We expect a single element, which
    % is the partition we have just created.
    [Partition] = guestfs:list_partitions(G),

    % Create a filesystem on the partition.
    ok = guestfs:mkfs(G, "ext4", Partition),

    % Now mount the filesystem so that we can add files. *)
    ok = guestfs:mount_options(G, "", Partition, "/"),

    % Create some files and directories. *)
    ok = guestfs:touch(G, "/empty"),
    Message = "Hello, world\n",
    ok = guestfs:write(G, "/hello", Message),
    ok = guestfs:mkdir(G, "/foo"),

    % This one uploads the local file /etc/resolv.conf into
    % the disk image.
    ok = guestfs:upload(G, "/etc/resolv.conf", "/foo/resolv.conf"),

    % Because we wrote to the disk and we want to detect write
    % errors, call guestfs:shutdown.  You don't need to do this:
    % guestfs:close will do it implicitly.
    ok = guestfs:shutdown(G),

    % Note also that handles are automatically closed if they are
    % reaped by the garbage collector.  You only need to call close
    % if you want to close the handle right away.
    ok = guestfs:close(G).
