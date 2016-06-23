(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Unix
open Printf

open Common_gettext.Gettext

module G = Guestfs

open Common_utils
open Types
open Utils

open Cmdline

type conversion_mode =
    | Copying of overlay list * target list
    | In_place

let () = Random.self_init ()

let rec main () =
  (* Handle the command line. *)
  let cmdline, input, output = parse_cmdline () in

  (* Print the version, easier than asking users to tell us. *)
  debug "%s: %s %s (%s)"
        prog Guestfs_config.package_name
        Guestfs_config.package_version Guestfs_config.host_cpu;

  let source = open_source cmdline input in
  let source = amend_source cmdline source in

  let conversion_mode =
    if not cmdline.in_place then (
      check_host_free_space ();
      let overlays = create_overlays source.s_disks in
      let targets = init_targets cmdline output source overlays in
      Copying (overlays, targets)
    )
    else In_place in

  (match conversion_mode with
   | Copying _ -> message (f_"Opening the overlay")
   | In_place -> message (f_"Opening the source VM")
  );

  let g = open_guestfs ~identifier:"v2v" () in
  g#set_memsize (g#get_memsize () * 8 / 5);
  g#set_network true;
  (match conversion_mode with
   | Copying (overlays, _) -> populate_overlays g overlays
   | In_place -> populate_disks g source.s_disks
  );

  g#launch ();

  (* Inspection - this also mounts up the filesystems. *)
  (match conversion_mode with
   | Copying _ -> message (f_"Inspecting the overlay")
   | In_place -> message (f_"Inspecting the source VM")
  );
  let inspect = Inspect_source.inspect_source cmdline.root_choice g in

  let mpstats = get_mpstats g in
  check_guest_free_space mpstats;
  (match conversion_mode with
   | Copying (_, targets) ->
       check_target_free_space mpstats source targets output
   | In_place -> ()
  );

  (* Conversion. *)
  let guestcaps =
    let keep_serial_console = output#keep_serial_console in
    do_convert g inspect source keep_serial_console in

  g#umount_all ();

  if cmdline.no_trim <> ["*"] &&
       (cmdline.do_copy || cmdline.debug_overlays) then (
    (* Doing fstrim on all the filesystems reduces the transfer size
     * because unused blocks are marked in the overlay and thus do
     * not have to be copied.
     *)
    message (f_"Mapping filesystem data to avoid copying unused and blank areas");
    do_fstrim g cmdline.no_trim inspect;
  );

  (match conversion_mode with
   | Copying _ -> message (f_"Closing the overlay")
   | In_place -> message (f_"Closing the source VM")
  );
  g#umount_all ();
  g#shutdown ();
  g#close ();

  (* Copy overlays to target (for [--in-place] this does nothing). *)
  (match conversion_mode with
   | In_place -> ()
   | Copying (overlays, targets) ->
       let target_firmware =
         get_target_firmware inspect guestcaps source output in

       message (f_"Assigning disks to buses");
       let target_buses =
         Target_bus_assignment.target_bus_assignment source targets
                                                     guestcaps in
       debug "%s" (string_of_target_buses target_buses);

       let targets =
         if not cmdline.do_copy then targets
         else copy_targets cmdline targets input output in

       (* Create output metadata. *)
       message (f_"Creating output metadata");
       output#create_metadata source targets target_buses guestcaps inspect
                             target_firmware;

       if cmdline.debug_overlays then preserve_overlays overlays source.s_name;

       delete_target_on_exit := false  (* Don't delete target on exit. *)
  );
  message (f_"Finishing off")

and open_source cmdline input =
  message (f_"Opening the source %s") input#as_options;
  let source = input#source () in

  (* Print source and stop. *)
  if cmdline.print_source then (
    printf (f_"Source guest information (--print-source option):\n");
    printf "\n";
    printf "%s\n" (string_of_source source);
    exit 0
  );

  debug "%s" (string_of_source source);

  (match source.s_hypervisor with
  | OtherHV hv ->
    warning (f_"unknown source hypervisor ('%s') in metadata") hv
  | _ -> ()
  );

  assert (source.s_name <> "");
  assert (source.s_memory > 0L);
  assert (source.s_vcpu >= 1);
  if source.s_disks = [] then
    error (f_"source has no hard disks!");
  List.iter (
    fun disk ->
      assert (disk.s_qemu_uri <> "");
  ) source.s_disks;

  source

and amend_source cmdline source =
  (* Map source name. *)
  let source =
    match cmdline.output_name with
    | None -> source
    (* Note the s_orig_name field retains the original name in case we
     * need it for some reason.
     *)
    | Some name -> { source with s_name = name } in

  (* Map networks and bridges. *)
  let nics = List.map (
    fun ({ s_vnet_type = t; s_vnet = vnet } as nic) ->
      try
        (* Look for a --network or --bridge parameter which names this
         * network/bridge (eg. --network in:out).
         *)
        let new_name = NetworkMap.find (t, Some vnet) cmdline.network_map in
        { nic with s_vnet = new_name }
      with Not_found ->
        try
          (* Not found, so look for a default mapping (eg. --network out). *)
          let new_name = NetworkMap.find (t, None) cmdline.network_map in
          { nic with s_vnet = new_name }
        with Not_found ->
          (* Not found, so return the original NIC unchanged. *)
          nic
  ) source.s_nics in

  { source with s_nics = nics }

and overlay_dir = (open_guestfs ())#get_cachedir ()

(* Conversion can fail or hang if there is insufficient free space in
 * the temporary directory used to store overlays on the host
 * (RHBZ#1316479).  Although only a few hundred MB is actually
 * required, make the minimum be 1 GB to allow for the possible 500 MB
 * guestfs appliance which is also stored here.
 *)
and check_host_free_space () =
  let free_space = StatVFS.free_space overlay_dir in
  debug "check_host_free_space: overlay_dir=%s free_space=%Ld"
        overlay_dir free_space;
  if free_space < 1_073_741_824L then
    error (f_"insufficient free space in the conversion server temporary directory %s (%s).\n\nEither free up space in that directory, or set the LIBGUESTFS_CACHEDIR environment variable to point to another directory with more than 1GB of free space.\n\nSee also the virt-v2v(1) manual, section \"Minimum free space check in the host\".")
          overlay_dir (human_size free_space)

(* Create a qcow2 v3 overlay to protect the source image(s). *)
and create_overlays src_disks =
  message (f_"Creating an overlay to protect the source from being modified");
  List.mapi (
    fun i ({ s_qemu_uri = qemu_uri; s_format = format } as source) ->
      let overlay_file =
        Filename.temp_file ~temp_dir:overlay_dir "v2vovl" ".qcow2" in
      unlink_on_exit overlay_file;

      (* There is a specific reason to use the newer qcow2 variant:
       * Because the L2 table can store zero clusters efficiently, and
       * because discarded blocks are stored as zero clusters, this
       * should allow us to fstrim/blkdiscard and avoid copying
       * significant parts of the data over the wire.
       *)
      let options =
        "compat=1.1" ^
          (match format with None -> ""
                           | Some fmt -> ",backing_fmt=" ^ fmt) in
      let cmd = [ "qemu-img"; "create"; "-q"; "-f"; "qcow2"; "-b"; qemu_uri;
                  "-o"; options; overlay_file ] in
      if run_command cmd <> 0 then
        error (f_"qemu-img command failed, see earlier errors");

      (* Sanity check created overlay (see below). *)
      if not ((open_guestfs ())#disk_has_backing_file overlay_file) then
        error (f_"internal error: qemu-img did not create overlay with backing file");

      let sd = "sd" ^ drive_name i in

      let vsize = (open_guestfs ())#disk_virtual_size overlay_file in

      (* If the virtual size is 0, then something went badly wrong.
       * It could be RHBZ#1283588 or some other problem with qemu.
       *)
      if vsize = 0L then
        error (f_"guest disk %s appears to be zero bytes in size.\n\nThere could be several reasons for this:\n\nCheck that the guest doesn't really have a zero-sized disk.  virt-v2v cannot convert such a guest.\n\nIf you are converting a guest from an ssh source and the guest has a disk on a block device (eg. on a host partition or host LVM LV), then conversions of this type are not supported.  See \"XEN OR SSH CONVERSIONS FROM BLOCK DEVICES\" in the virt-v2v(1) manual for a workaround.")
              sd;

      { ov_overlay_file = overlay_file; ov_sd = sd;
        ov_virtual_size = vsize; ov_source = source }
  ) src_disks

(* Work out where we will write the final output.  Do this early
 * just so we can display errors to the user before doing too much
 * work.
 *)
and init_targets cmdline output source overlays =
  message (f_"Initializing the target %s") output#as_options;
  let targets =
    List.map (
      fun ov ->
        (* What output format should we use? *)
        let format =
          match cmdline.output_format, ov.ov_source.s_format with
          | Some format, _ -> format    (* -of overrides everything *)
          | None, Some format -> format (* same as backing format *)
          | None, None ->
            error (f_"disk %s (%s) has no defined format.\n\nThe input metadata did not define the disk format (eg. raw/qcow2/etc) of this disk, and so virt-v2v will try to autodetect the format when reading it.\n\nHowever because the input format was not defined, we do not know what output format you want to use.  You have two choices: either define the original format in the source metadata, or use the '-of' option to force the output format.") ov.ov_sd ov.ov_source.s_qemu_uri in

        (* What really happens here is that the call to #disk_create
         * below fails if the format is not raw or qcow2.  We would
         * have to extend libguestfs to support further formats, which
         * is trivial, but we'd want to check that the files being
         * created by qemu-img really work.  In any case, fail here,
         * early, not below, later.
         *)
        if format <> "raw" && format <> "qcow2" then
          error (f_"output format should be 'raw' or 'qcow2'.\n\nUse the '-of <format>' option to select a different output format for the converted guest.\n\nOther output formats are not supported at the moment, although might be considered in future.");

        (* Only allow compressed with qcow2. *)
        if cmdline.compressed && format <> "qcow2" then
          error (f_"the --compressed flag is only allowed when the output format is qcow2 (-of qcow2)");

        (* output#prepare_targets will fill in the target_file field.
         * estimate_target_size will fill in the target_estimated_size field.
         * actual_target_size will fill in the target_actual_size field.
         *)
        { target_file = ""; target_format = format;
          target_estimated_size = None;
          target_actual_size = None;
          target_overlay = ov }
    ) overlays in

  output#prepare_targets source targets

(* Populate guestfs handle with qcow2 overlays. *)
and populate_overlays g overlays =
  List.iter (
    fun ({ov_overlay_file = overlay_file}) ->
      g#add_drive_opts overlay_file
        ~format:"qcow2" ~cachemode:"unsafe" ~discard:"besteffort"
        ~copyonread:true
  ) overlays

(* Populate guestfs handle with source disks.  Only used for [--in-place]. *)
and populate_disks g src_disks =
  List.iter (
    fun ({s_qemu_uri = qemu_uri; s_format = format}) ->
      g#add_drive_opts qemu_uri ?format ~cachemode:"unsafe"
                          ~discard:"besteffort"
  ) src_disks

(* Collect statvfs information from the guest mountpoints. *)
and get_mpstats g =
  let mpstats = List.map (
    fun (dev, path) ->
      let statvfs = g#statvfs path in
      let vfs = g#vfs_type dev in
      { mp_dev = dev; mp_path = path; mp_statvfs = statvfs; mp_vfs = vfs }
  ) (g#mountpoints ()) in

  if verbose () then (
    (* This is useful for debugging speed / fstrim issues. *)
    eprintf "mpstats:\n";
    List.iter (print_mpstat Pervasives.stderr) mpstats
  );

  mpstats

(* Conversion can fail if there is no space on the guest filesystems
 * (RHBZ#1139543).  To avoid this situation, check there is some
 * headroom.  Mainly we care about the root filesystem.
 *)
and check_guest_free_space mpstats =
  message (f_"Checking for sufficient free disk space in the guest");
  List.iter (
    fun { mp_path = mp;
          mp_statvfs = { G.bfree = bfree; blocks = blocks; bsize = bsize } } ->
      (* Ignore small filesystems. *)
      let total_size = blocks *^ bsize in
      if total_size > 100_000_000L then (
        (* bfree = free blocks for root user *)
        let free_bytes = bfree *^ bsize in
        let needed_bytes =
          match mp with
          | "/" ->
            (* We may install some packages, and they would usually go
             * on the root filesystem.
             *)
            20_000_000L
          | "/boot" ->
            (* We usually regenerate the initramfs, which has a
             * typical size of 20-30MB.  Hence:
             *)
            50_000_000L
          | _ ->
            (* For everything else, just make sure there is some free space. *)
            10_000_000L in

        if free_bytes < needed_bytes then
          error (f_"not enough free space for conversion on filesystem '%s'.  %Ld bytes free < %Ld bytes needed")
            mp free_bytes needed_bytes
      )
  ) mpstats

(* Perform the fstrim.  The trimming bit is easy.  Dealing with the
 * [--no-trim] parameter .. not so much.
 *)
and do_fstrim g no_trim inspect =
  (* Get all filesystems. *)
  let fses = g#list_filesystems () in

  let fses = filter_map (
    function (_, ("unknown"|"swap")) -> None | (dev, _) -> Some dev
  ) fses in

  let fses =
    if no_trim = [] then fses
    else (
      if verbose () then (
        printf "no_trim: %s\n" (String.concat " " no_trim);
        printf "filesystems before considering no_trim: %s\n"
          (String.concat " " fses)
      );

      (* Drop any filesystems that match a device name in the no_trim list. *)
      let fses = List.filter (
        fun dev ->
          not (List.mem (g#canonical_device_name dev) no_trim)
      ) fses in

      (* Drop any mountpoints matching the no_trim list. *)
      let dev_to_mp =
        List.map (fun (mp, dev) -> g#canonical_device_name dev, mp)
          inspect.i_mountpoints in
      let fses = List.filter (
        fun dev ->
          try not (List.mem (List.assoc dev dev_to_mp) no_trim)
          with Not_found -> true
      ) fses in

      if verbose () then
        printf "filesystems after considering no_trim: %s\n%!"
          (String.concat " " fses);

      fses
    ) in

  (* Trim the remaining filesystems. *)
  List.iter (
    fun dev ->
      g#umount_all ();
      let mounted = try g#mount dev "/"; true with G.Error _ -> false in
      if mounted then (
        try g#fstrim "/"
        with G.Error msg ->
          (* Only emit this warning when debugging, because otherwise
           * it causes distress (RHBZ#1168144).
           *)
          if verbose () then
            warning (f_"%s (ignored)") msg
      )
  ) fses

(* Estimate the space required on the target for each disk.  It is the
 * maximum space that might be required, but in reasonable cases much
 * less space would actually be needed.
 *
 * As a starting point we could take ov_virtual_size (plus a tiny
 * overhead for qcow2 headers etc) as the maximum.  However that's not
 * very useful.  Other information we have available is:
 *
 * - The list of filesystems across the source disk(s).
 *
 * - The disk used/free of each of those filesystems, and the
 * filesystem type.
 *
 * Note that we do NOT have the used size of the source disk (because
 * it may be remote).
 *
 * How do you attribute filesystem usage through to backing disks,
 * since one filesystem might span multiple disks?
 *
 * How do you account for non-filesystem usage (eg. swap, partitions
 * that libguestfs cannot read, the space between LVs/partitions)?
 *
 * Another wildcard is that although we try to run {c fstrim} on each
 * source filesystem, it can fail in some common scenarios.  Also
 * qemu-img will do zero detection.  Both of these can be big wins when
 * they work.
 *
 * The algorithm used here is this:
 *
 * (1) Calculate the total virtual size of all guest filesystems.
 * eg: [ "/boot" = 500 MB, "/" = 2.5 GB ], total = 3 GB
 *
 * (2) Calculate the total virtual size of all source disks.
 * eg: [ sda = 1 GB, sdb = 3 GB ], total = 4 GB
 *
 * (3) The ratio of (1):(2) is the maximum that could be freed up if
 * all filesystems were effectively zeroed out during the conversion.
 * eg. ratio = 3/4
 *
 * (4) Work out how much filesystem space we are likely to save if
 * fstrim works, but exclude a few cases where fstrim will probably
 * fail (eg. filesystems that don't support fstrim).  This is the
 * conversion saving.
 * eg. [ "/boot" = 200 MB used, "/" = 1 GB used ], saving = 3 - 1.2 = 1.8
 *
 * (5) Scale the conversion saving (4) by the ratio (3), and allocate
 * that saving across all source disks in proportion to their
 * virtual size.
 * eg. scaled saving is 1.8 * 3/4 = 1.35 GB
 *     sda has 1/4 of total virtual size, so it gets a saving of 1.35/4
 *     sda final estimated size = 1 - (1.35/4) = 0.6625 GB
 *     sdb has 3/4 of total virtual size, so it gets a saving of 3 * 1.35 / 4
 *     sdb final estimate size = 3 - (3*1.35/4) = 1.9875 GB
 *)
and estimate_target_size mpstats targets =
  let sum = List.fold_left (+^) 0L in

  (* (1) *)
  let fs_total_size =
    sum (
      List.map (fun { mp_statvfs = s } -> s.G.blocks *^ s.G.bsize) mpstats
    ) in
  debug "estimate_target_size: fs_total_size = %Ld [%s]"
        fs_total_size (human_size fs_total_size);

  (* (2) *)
  let source_total_size =
    sum (List.map (fun t -> t.target_overlay.ov_virtual_size) targets) in
  debug "estimate_target_size: source_total_size = %Ld [%s]"
        source_total_size (human_size source_total_size);

  if source_total_size = 0L then     (* Avoid divide by zero error. *)
    targets
  else (
    (* (3) Store the ratio as a float to avoid overflows later. *)
    let ratio =
      Int64.to_float fs_total_size /. Int64.to_float source_total_size in
    debug "estimate_target_size: ratio = %.3f" ratio;

    (* (4) *)
    let fs_free =
      sum (
        List.map (
          function
          (* On filesystems supported by fstrim, assume we can save all
           * the free space.
           *)
          | { mp_vfs = "ext2"|"ext3"|"ext4"|"xfs"; mp_statvfs = s } ->
            s.G.bfree *^ s.G.bsize

          (* fstrim is only supported on NTFS very recently, and has a
           * lot of limitations.  So make the safe assumption for now
           * that it's not going to work.
           *)
          | { mp_vfs = "ntfs" } -> 0L

          (* For other filesystems, sorry we can't free anything :-/ *)
          | _ -> 0L
        ) mpstats
      ) in
    debug "estimate_target_size: fs_free = %Ld [%s]"
          fs_free (human_size fs_free);
    let scaled_saving = Int64.of_float (Int64.to_float fs_free *. ratio) in
    debug "estimate_target_size: scaled_saving = %Ld [%s]"
          scaled_saving (human_size scaled_saving);

    (* (5) *)
    let targets = List.map (
      fun ({ target_overlay = ov } as t) ->
        let size = ov.ov_virtual_size in
        let proportion =
          Int64.to_float size /. Int64.to_float source_total_size in
        let estimated_size =
          size -^ Int64.of_float (proportion *. Int64.to_float scaled_saving) in
        debug "estimate_target_size: %s: %Ld [%s]"
              ov.ov_sd estimated_size (human_size estimated_size);
        { t with target_estimated_size = Some estimated_size }
    ) targets in

    targets
  )

(* Estimate space required on target for each disk.  Note this is a max. *)
and check_target_free_space mpstats source targets output =
  message (f_"Estimating space required on target for each disk");
  let targets = estimate_target_size mpstats targets in

  output#check_target_free_space source targets

(* Conversion. *)
and do_convert g inspect source keep_serial_console =
  (match inspect.i_product_name with
  | "unknown" ->
    message (f_"Converting the guest to run on KVM")
  | prod ->
    message (f_"Converting %s to run on KVM") prod
  );

  let conversion_name, convert =
    try Modules_list.find_convert_module inspect
    with Not_found ->
      error (f_"virt-v2v is unable to convert this guest type (%s/%s)")
        inspect.i_type inspect.i_distro in
  debug "picked conversion module %s" conversion_name;
  let guestcaps = convert ~keep_serial_console g inspect source in
  debug "%s" (string_of_guestcaps guestcaps);

  (* Did we manage to install virtio drivers? *)
  if not (quiet ()) then (
    if guestcaps.gcaps_block_bus = Virtio_blk then
      info (f_"This guest has virtio drivers installed.")
    else
      info (f_"This guest does not have virtio drivers installed.");
  );

  guestcaps

(* Does the guest require UEFI on the target? *)
and get_target_firmware inspect guestcaps source output =
  message (f_"Checking if the guest needs BIOS or UEFI to boot");
  let target_firmware =
    match source.s_firmware with
    | BIOS -> TargetBIOS
    | UEFI -> TargetUEFI
    | UnknownFirmware ->
       if inspect.i_uefi then TargetUEFI else TargetBIOS in
  let supported_firmware = output#supported_firmware in
  if not (List.mem target_firmware supported_firmware) then
    error (f_"this guest cannot run on the target, because the target does not support %s firmware (supported firmware on target: %s)")
          (string_of_target_firmware target_firmware)
          (String.concat " "
            (List.map string_of_target_firmware supported_firmware));

  output#check_target_firmware guestcaps target_firmware;

  (match target_firmware with
   | TargetBIOS -> ()
   | TargetUEFI -> info (f_"This guest requires UEFI on the target to boot."));

  target_firmware

and delete_target_on_exit = ref true

(* Copy the source (really, the overlays) to the output. *)
and copy_targets cmdline targets input output =
  at_exit (fun () ->
    if !delete_target_on_exit then (
      List.iter (
        fun t -> try unlink t.target_file with _ -> ()
      ) targets
    )
  );
  let nr_disks = List.length targets in
  mapi (
    fun i t ->
      message (f_"Copying disk %d/%d to %s (%s)")
        (i+1) nr_disks t.target_file t.target_format;
      debug "%s" (string_of_target t);

      (* We noticed that qemu sometimes corrupts the qcow2 file on
       * exit.  This only seemed to happen with lazy_refcounts was
       * used.  The symptom was that the header wasn't written back
       * to the disk correctly and the file appeared to have no
       * backing file.  Just sanity check this here.
       *)
      let overlay_file = t.target_overlay.ov_overlay_file in
      if not ((open_guestfs ())#disk_has_backing_file overlay_file) then
        error (f_"internal error: qemu corrupted the overlay file");

      (* Give the input module a chance to adjust the parameters
       * of the overlay/backing file.  This allows us to increase
       * the readahead parameter when copying (see RHBZ#1151033 and
       * RHBZ#1153589 for the gruesome details).
       *)
      input#adjust_overlay_parameters t.target_overlay;

      (* It turns out that libguestfs's disk creation code is
       * considerably more flexible and easier to use than
       * qemu-img, so create the disk explicitly using libguestfs
       * then pass the 'qemu-img convert -n' option so qemu reuses
       * the disk.
       *
       * Also we allow the output mode to actually create the disk
       * image.  This lets the output mode set ownership and
       * permissions correctly if required.
       *)
      (* What output preallocation mode should we use? *)
      let preallocation =
        match t.target_format, cmdline.output_alloc with
        | ("raw"|"qcow2"), Sparse -> Some "sparse"
        | ("raw"|"qcow2"), Preallocated -> Some "full"
        | _ -> None (* ignore -oa flag for other formats *) in
      let compat =
        match t.target_format with "qcow2" -> Some "1.1" | _ -> None in
      output#disk_create
        t.target_file t.target_format t.target_overlay.ov_virtual_size
        ?preallocation ?compat;

      let cmd = [ "qemu-img"; "convert" ] @
        (if not (quiet ()) then [ "-p" ] else []) @
        [ "-n"; "-f"; "qcow2"; "-O"; t.target_format ] @
        (if cmdline.compressed then [ "-c" ] else []) @
        [ overlay_file; t.target_file ] in
      let start_time = gettimeofday () in
      if run_command cmd <> 0 then
        error (f_"qemu-img command failed, see earlier errors");
      let end_time = gettimeofday () in

      (* Calculate the actual size on the target, returns an updated
       * target structure.
       *)
      let t = actual_target_size t in

      (* If verbose, print the virtual and real copying rates. *)
      let elapsed_time = end_time -. start_time in
      if verbose () && elapsed_time > 0. then (
        let mbps size time =
          Int64.to_float size /. 1024. /. 1024. *. 10. /. time
        in

        eprintf "virtual copying rate: %.1f M bits/sec\n%!"
          (mbps t.target_overlay.ov_virtual_size elapsed_time);

        match t.target_actual_size with
        | None -> ()
        | Some actual ->
           eprintf "real copying rate: %.1f M bits/sec\n%!"
                   (mbps actual elapsed_time)
      );

      (* If verbose, find out how close the estimate was.  This is
       * for developer information only - so we can increase the
       * accuracy of the estimate.
       *)
      if verbose () then (
        match t.target_estimated_size, t.target_actual_size with
        | None, None | None, Some _ | Some _, None | Some _, Some 0L -> ()
        | Some estimate, Some actual ->
          let pc =
            100. *. Int64.to_float estimate /. Int64.to_float actual
            -. 100. in
          eprintf "%s: estimate %Ld (%s) versus actual %Ld (%s): %.1f%%"
            t.target_overlay.ov_sd
            estimate (human_size estimate)
            actual (human_size actual)
            pc;
          if pc < 0. then eprintf " ! ESTIMATE TOO LOW !";
          eprintf "\n%!";
      );

      t
  ) targets

(* Update the target_actual_size field in the target structure. *)
and actual_target_size target =
  let size =
    (* Ignore errors because we want to avoid failures after copying. *)
    try Some (du target.target_file)
    with Failure _ | Invalid_argument _ -> None in
  { target with target_actual_size = size }

(* Save overlays if --debug-overlays option was used. *)
and preserve_overlays overlays src_name =
  List.iter (
    fun ov ->
      let saved_filename =
        sprintf "%s/%s-%s.qcow2" overlay_dir src_name ov.ov_sd in
      rename ov.ov_overlay_file saved_filename;
      info (f_"Overlay saved as %s [--debug-overlays]") saved_filename
  ) overlays

let () = run_main_and_handle_errors main
