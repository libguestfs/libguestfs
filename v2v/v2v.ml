(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(* Mountpoint stats, used for free space estimation. *)
type mpstat = {
  mp_dev : string;                      (* Filesystem device (eg. /dev/sda1) *)
  mp_path : string;                     (* Guest mountpoint (eg. /boot) *)
  mp_statvfs : Guestfs.statvfs;         (* Free space stats. *)
  mp_vfs : string;                      (* VFS type (eg. "ext4") *)
}

let print_mpstat chan { mp_dev = dev; mp_path = path;
                        mp_statvfs = s; mp_vfs = vfs } =
  fprintf chan "mountpoint statvfs %s %s (%s):\n" dev path vfs;
  fprintf chan "  bsize=%Ld blocks=%Ld bfree=%Ld bavail=%Ld\n"
    s.G.bsize s.G.blocks s.G.bfree s.G.bavail

let () = Random.self_init ()

let rec main () =
  (* Handle the command line. *)
  let input, output,
    debug_gc, debug_overlays, do_copy, network_map, no_trim,
    output_alloc, output_format, output_name,
    print_source, quiet, root_choice, trace, verbose =
    Cmdline.parse_cmdline () in

  let msg fs = make_message_function ~quiet fs in

  (* Print the version, easier than asking users to tell us. *)
  if verbose then
    printf "%s: %s %s (%s)\n%!"
      prog Config.package_name Config.package_version Config.host_cpu;

  msg (f_"Opening the source %s") input#as_options;
  let source = input#source () in

  (* Print source and stop. *)
  if print_source then (
    printf (f_"Source guest information (--print-source option):\n");
    printf "\n";
    printf "%s\n" (string_of_source source);
    if debug_gc then
      Gc.compact ();
    exit 0
  );

  if verbose then printf "%s%!" (string_of_source source);

  assert (source.s_dom_type <> "");
  assert (source.s_name <> "");
  assert (source.s_memory > 0L);
  assert (source.s_vcpu >= 1);
  if source.s_disks = [] then
    error (f_"source has no hard disks!");
  List.iter (
    fun disk ->
      assert (disk.s_qemu_uri <> "");
  ) source.s_disks;

  (* Map source name. *)
  let source =
    match output_name with
    | None -> source
    (* Note the s_orig_name field retains the original name in case we
     * need it for some reason.
     *)
    | Some name -> { source with s_name = name } in

  (* Map networks and bridges. *)
  let source =
    let { s_nics = nics } = source in
    let nics = List.map (
      fun ({ s_vnet_type = t; s_vnet = vnet } as nic) ->
        try
          (* Look for a --network or --bridge parameter which names this
           * network/bridge (eg. --network in:out).
           *)
          let new_name = List.assoc (t, vnet) network_map in
          { nic with s_vnet = new_name }
        with Not_found ->
          try
            (* Not found, so look for a default mapping (eg. --network out). *)
            let new_name = List.assoc (t, "") network_map in
            { nic with s_vnet = new_name }
          with Not_found ->
            (* Not found, so return the original NIC unchanged. *)
            nic
    ) nics in
    { source with s_nics = nics } in

  (* Create a qcow2 v3 overlay to protect the source image(s).  There
   * is a specific reason to use the newer qcow2 variant: Because the
   * L2 table can store zero clusters efficiently, and because
   * discarded blocks are stored as zero clusters, this should allow us
   * to fstrim/blkdiscard and avoid copying significant parts of the
   * data over the wire.
   *)
  msg (f_"Creating an overlay to protect the source from being modified");
  let overlay_dir = (new Guestfs.guestfs ())#get_cachedir () in
  let overlays =
    List.map (
      fun ({ s_qemu_uri = qemu_uri; s_format = format } as source) ->
        let overlay_file =
          Filename.temp_file ~temp_dir:overlay_dir "v2vovl" ".qcow2" in
        unlink_on_exit overlay_file;

        let options =
          "compat=1.1" ^
            (match format with None -> ""
            | Some fmt -> ",backing_fmt=" ^ fmt) in
        let cmd =
          sprintf "qemu-img create -q -f qcow2 -b %s -o %s %s"
            (quote qemu_uri) (quote options) overlay_file in
        if verbose then printf "%s\n%!" cmd;
        if Sys.command cmd <> 0 then
          error (f_"qemu-img command failed, see earlier errors");

        (* Sanity check created overlay (see below). *)
        if not ((new G.guestfs ())#disk_has_backing_file overlay_file) then
          error (f_"internal error: qemu-img did not create overlay with backing file");

        overlay_file, source
    ) source.s_disks in

  (* Open the guestfs handle. *)
  msg (f_"Opening the overlay");
  let g = new G.guestfs () in
  if trace then g#set_trace true;
  if verbose then g#set_verbose true;
  g#set_network true;
  List.iter (
    fun (overlay_file, _) ->
      g#add_drive_opts overlay_file
        ~format:"qcow2" ~cachemode:"unsafe" ~discard:"besteffort"
        ~copyonread:true
  ) overlays;

  g#launch ();

  let overlays =
    mapi (
      fun i (overlay_file, source) ->
        (* Grab the virtual size of each disk. *)
        let sd = "sd" ^ drive_name i in
        let dev = "/dev/" ^ sd in
        let vsize = g#blockdev_getsize64 dev in

        { ov_overlay_file = overlay_file; ov_sd = sd;
          ov_virtual_size = vsize; ov_source = source }
    ) overlays in

  (* Work out where we will write the final output.  Do this early
   * just so we can display errors to the user before doing too much
   * work.
   *)
  msg (f_"Initializing the target %s") output#as_options;
  let targets =
    List.map (
      fun ov ->
        (* What output format should we use? *)
        let format =
          match output_format, ov.ov_source.s_format with
          | Some format, _ -> format    (* -of overrides everything *)
          | None, Some format -> format (* same as backing format *)
          | None, None ->
            error (f_"disk %s (%s) has no defined format.\n\nThe input metadata did not define the disk format (eg. raw/qcow2/etc) of this disk, and so virt-v2v will try to autodetect the format when reading it.\n\nHowever because the input format was not defined, we do not know what output format you want to use.  You have two choices: either define the original format in the source metadata, or use the '-of' option to force the output format") ov.ov_sd ov.ov_source.s_qemu_uri in

        (* What really happens here is that the call to #disk_create
         * below fails if the format is not raw or qcow2.  We would
         * have to extend libguestfs to support further formats, which
         * is trivial, but we'd want to check that the files being
         * created by qemu-img really work.  In any case, fail here,
         * early, not below, later.
         *)
        if format <> "raw" && format <> "qcow2" then
          error (f_"output format should be 'raw' or 'qcow2'.\n\nUse the '-of <format>' option to select a different output format for the converted guest.\n\nOther output formats are not supported at the moment, although might be considered in future.");

        (* output#prepare_targets will fill in the target_file field.
         * estimate_target_size will fill in the target_estimated_size field.
         * actual_target_size will fill in the target_actual_size field.
         *)
        { target_file = ""; target_format = format;
          target_estimated_size = None;
          target_actual_size = None;
          target_overlay = ov }
    ) overlays in
  let targets = output#prepare_targets source targets in

  (* Inspection - this also mounts up the filesystems. *)
  msg (f_"Inspecting the overlay");
  let inspect = inspect_source g root_choice in

  (* The guest free disk space check and the target free space
   * estimation both require statvfs information from mountpoints, so
   * get that information first.
   *)
  let mpstats = List.map (
    fun (dev, path) ->
      let statvfs = g#statvfs path in
      let vfs = g#vfs_type dev in
      { mp_dev = dev; mp_path = path; mp_statvfs = statvfs; mp_vfs = vfs }
  ) (g#mountpoints ()) in

  if verbose then (
    (* This is useful for debugging speed / fstrim issues. *)
    printf "mpstats:\n";
    List.iter (print_mpstat Pervasives.stdout) mpstats
  );

  (* Check there is enough free space to perform conversion. *)
  msg (f_"Checking for sufficient free disk space in the guest");
  check_free_space mpstats;

  (* Estimate space required on target for each disk.  Note this is a max. *)
  msg (f_"Estimating space required on target for each disk");
  let targets = estimate_target_size ~verbose mpstats targets in

  output#check_target_free_space source targets;

  (* Conversion. *)
  let guestcaps =
    (match inspect.i_product_name with
    | "unknown" ->
      msg (f_"Converting the guest to run on KVM")
    | prod ->
      msg (f_"Converting %s to run on KVM") prod
    );

    (* RHEV doesn't support serial console so remove any on conversion. *)
    let keep_serial_console = output#keep_serial_console in

    let conversion_name, convert =
      try Modules_list.find_convert_module inspect
      with Not_found ->
        error (f_"virt-v2v is unable to convert this guest type (%s/%s)")
          inspect.i_type inspect.i_distro in
    if verbose then printf "picked conversion module %s\n%!" conversion_name;
    convert ~verbose ~keep_serial_console g inspect source in

  (* Did we manage to install virtio drivers? *)
  if not quiet then (
    if guestcaps.gcaps_block_bus = Virtio_blk then
      info ~prog (f_"This guest has virtio drivers installed.")
    else
      info ~prog (f_"This guest does not have virtio drivers installed.");
  );

  g#umount_all ();

  if no_trim <> ["*"] && (do_copy || debug_overlays) then (
    (* Doing fstrim on all the filesystems reduces the transfer size
     * because unused blocks are marked in the overlay and thus do
     * not have to be copied.
     *)
    msg (f_"Mapping filesystem data to avoid copying unused and blank areas");
    do_fstrim ~verbose g no_trim inspect;
  );

  msg (f_"Closing the overlay");
  g#umount_all ();
  g#shutdown ();
  g#close ();

  let delete_target_on_exit = ref true in

  let targets =
    if not do_copy then targets
    else (
      (* Copy the source to the output. *)
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
          msg (f_"Copying disk %d/%d to %s (%s)")
            (i+1) nr_disks t.target_file t.target_format;
          if verbose then printf "%s%!" (string_of_target t);

          (* We noticed that qemu sometimes corrupts the qcow2 file on
           * exit.  This only seemed to happen with lazy_refcounts was
           * used.  The symptom was that the header wasn't written back
           * to the disk correctly and the file appeared to have no
           * backing file.  Just sanity check this here.
           *)
          let overlay_file = t.target_overlay.ov_overlay_file in
          if not ((new G.guestfs ())#disk_has_backing_file overlay_file) then
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
            match t.target_format, output_alloc with
            | "raw", `Sparse -> Some "sparse"
            | "raw", `Preallocated -> Some "full"
            | "qcow2", `Sparse -> Some "off" (* ? *)
            | "qcow2", `Preallocated -> Some "metadata"
            | _ -> None (* ignore -oa flag for other formats *) in
          let compat =
            match t.target_format with "qcow2" -> Some "1.1" | _ -> None in
          output#disk_create
            t.target_file t.target_format t.target_overlay.ov_virtual_size
            ?preallocation ?compat;

          let cmd =
            sprintf "qemu-img convert%s -n -f qcow2 -O %s %s %s"
              (if not quiet then " -p" else "")
              (quote t.target_format) (quote overlay_file)
              (quote t.target_file) in
          if verbose then printf "%s\n%!" cmd;
          let start_time = gettimeofday () in
          if Sys.command cmd <> 0 then
            error (f_"qemu-img command failed, see earlier errors");
          let end_time = gettimeofday () in

          (* Calculate the actual size on the target, returns an updated
           * target structure.
           *)
          let t = actual_target_size t in

          (* If verbose, print the virtual and real copying rates. *)
          let elapsed_time = end_time -. start_time in
          if verbose && elapsed_time > 0. then (
            let rate =
              Int64.to_float t.target_overlay.ov_virtual_size
              /. 1024. /. 1024. *. 10. /. elapsed_time in
            printf "virtual copying rate: %.1f M bits/sec\n%!" rate;

            match t.target_actual_size with
            | None -> ()
            | Some actual ->
              let rate =
                Int64.to_float actual /. 1024. /. 1024. *. 10. /. elapsed_time in
              printf "real copying rate: %.1f M bits/sec\n%!" rate
          );

          (* If verbose, find out how close the estimate was.  This is
           * for developer information only - so we can increase the
           * accuracy of the estimate.
           *)
          if verbose then (
            match t.target_estimated_size, t.target_actual_size with
            | None, None | None, Some _ | Some _, None | Some _, Some 0L -> ()
            | Some estimate, Some actual ->
              let pc =
                100. *. Int64.to_float estimate /. Int64.to_float actual
                -. 100. in
              printf "%s: estimate %Ld (%s) versus actual %Ld (%s): %.1f%%"
                t.target_overlay.ov_sd
                estimate (human_size estimate)
                actual (human_size actual)
                pc;
              if pc < 0. then printf " ! ESTIMATE TOO LOW !";
              printf "\n%!";
          );

          t
      ) targets
    ) (* do_copy *) in

  (* Create output metadata. *)
  msg (f_"Creating output metadata");
  output#create_metadata source targets guestcaps inspect;

  (* Save overlays if --debug-overlays option was used. *)
  if debug_overlays then (
    List.iter (
      fun ov ->
        let saved_filename =
          sprintf "%s/%s-%s.qcow2" overlay_dir source.s_name ov.ov_sd in
        rename ov.ov_overlay_file saved_filename;
        printf (f_"Overlay saved as %s [--debug-overlays]\n") saved_filename
    ) overlays
  );

  msg (f_"Finishing off");
  delete_target_on_exit := false;  (* Don't delete target on exit. *)

  if debug_gc then
    Gc.compact ()

and inspect_source g root_choice =
  let roots = g#inspect_os () in
  let roots = Array.to_list roots in

  let root =
    match roots with
    | [] ->
      error (f_"no root device found in this operating system image.");
    | [root] -> root
    | roots ->
      match root_choice with
      | `Ask ->
        (* List out the roots and ask the user to choose. *)
        printf "\n***\n";
        printf (f_"Dual- or multi-boot operating system detected.  Choose the root filesystem\nthat contains the main operating system from the list below:\n");
        printf "\n";
        iteri (
          fun i root ->
            let prod = g#inspect_get_product_name root in
            match prod with
            | "unknown" -> printf " [%d] %s\n" (i+1) root
            | prod -> printf " [%d] %s (%s)\n" (i+1) root prod
        ) roots;
        printf "\n";
        let i = ref 0 in
        let n = List.length roots in
        while !i < 1 || !i > n do
          printf (f_"Enter a number between 1 and %d, or 'exit': ") n;
          let input = read_line () in
          if input = "exit" || input = "q" || input = "quit" then
            exit 0
          else (
            try i := int_of_string input
            with
            | End_of_file -> error (f_"connection closed")
            | Failure "int_of_string" -> ()
          )
        done;
        List.nth roots (!i - 1)

      | `Single ->
        error (f_"multi-boot operating systems are not supported by virt-v2v. Use the --root option to change how virt-v2v handles this.")

      | `First ->
        let root = List.hd roots in
        info ~prog (f_"Picked %s because '--root first' was used.") root;
        root

      | `Dev dev ->
        let root =
          if List.mem dev roots then dev
          else
            error (f_"root device %s not found.  Roots found were: %s")
              dev (String.concat " " roots) in
        info ~prog (f_"Picked %s because '--root %s' was used.") root dev;
        root in

  (* Reject this OS if it doesn't look like an installed image. *)
  let () =
    let fmt = g#inspect_get_format root in
    if fmt <> "installed" then
      error (f_"libguestfs thinks this is not an installed operating system (it might be, for example, an installer disk or live CD).  If this is wrong, it is probably a bug in libguestfs.  root=%s fmt=%s") root fmt in

  (* Mount up the filesystems. *)
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (
    fun (mp, dev) ->
      try g#mount dev mp
      with G.Error msg ->
        if mp = "/" then ( (* RHBZ#1145995 *)
          if string_find msg "Windows" >= 0 && string_find msg "NTFS partition is in an unsafe state" >= 0 then
            error (f_"unable to mount the disk image for writing. This has probably happened because Windows Hibernation or Fast Restart is being used in this guest. You have to disable this (in the guest) in order to use virt-v2v.\n\nOriginal error message: %s") msg
          else
            error "%s" msg
        )
        else
          warning ~prog (f_"%s (ignored)") msg
  ) mps;

  (* Get list of applications/packages installed. *)
  let apps = g#inspect_list_applications2 root in
  let apps = Array.to_list apps in

  (* A map of app2_name -> application2, for easier lookups.  Note
   * that app names are not unique!  (eg. 'kernel' can appear multiple
   * times)
   *)
  let apps_map = List.fold_left (
    fun map app ->
      let name = app.G.app2_name in
      let vs = try StringMap.find name map with Not_found -> [] in
      StringMap.add name (app :: vs) map
  ) StringMap.empty apps in

  { i_root = root;
    i_type = g#inspect_get_type root;
    i_distro = g#inspect_get_distro root;
    i_arch = g#inspect_get_arch root;
    i_major_version = g#inspect_get_major_version root;
    i_minor_version = g#inspect_get_minor_version root;
    i_package_format = g#inspect_get_package_format root;
    i_package_management = g#inspect_get_package_management root;
    i_product_name = g#inspect_get_product_name root;
    i_product_variant = g#inspect_get_product_variant root;
    i_mountpoints = mps;
    i_apps = apps;
    i_apps_map = apps_map; }

(* Conversion can fail if there is no space on the guest filesystems
 * (RHBZ#1139543).  To avoid this situation, check there is some
 * headroom.  Mainly we care about the root filesystem.
 *)
and check_free_space mpstats =
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
and do_fstrim ~verbose g no_trim inspect =
  (* Get all filesystems. *)
  let fses = g#list_filesystems () in

  let fses = filter_map (
    function (_, ("unknown"|"swap")) -> None | (dev, _) -> Some dev
  ) fses in

  let fses =
    if no_trim = [] then fses
    else (
      if verbose then (
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

      if verbose then
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
          if verbose then
            warning ~prog (f_"%s (ignored)") msg
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
and estimate_target_size ~verbose mpstats targets =
  let sum = List.fold_left (+^) 0L in

  (* (1) *)
  let fs_total_size =
    sum (
      List.map (fun { mp_statvfs = s } -> s.G.blocks *^ s.G.bsize) mpstats
    ) in
  if verbose then
    printf "estimate_target_size: fs_total_size = %Ld [%s]\n%!"
      fs_total_size (human_size fs_total_size);

  (* (2) *)
  let source_total_size =
    sum (List.map (fun t -> t.target_overlay.ov_virtual_size) targets) in
  if verbose then
    printf "estimate_target_size: source_total_size = %Ld [%s]\n%!"
      source_total_size (human_size source_total_size);

  if source_total_size = 0L then     (* Avoid divide by zero error. *)
    targets
  else (
    (* (3) Store the ratio as a float to avoid overflows later. *)
    let ratio =
      Int64.to_float fs_total_size /. Int64.to_float source_total_size in
    if verbose then
      printf "estimate_target_size: ratio = %.3f\n%!" ratio;

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
    if verbose then
      printf "estimate_target_size: fs_free = %Ld [%s]\n%!"
        fs_free (human_size fs_free);
    let scaled_saving = Int64.of_float (Int64.to_float fs_free *. ratio) in
    if verbose then
      printf "estimate_target_size: scaled_saving = %Ld [%s]\n%!"
        scaled_saving (human_size scaled_saving);

    (* (5) *)
    let targets = List.map (
      fun ({ target_overlay = ov } as t) ->
        let size = ov.ov_virtual_size in
        let proportion =
          Int64.to_float size /. Int64.to_float source_total_size in
        let estimated_size =
          size -^ Int64.of_float (proportion *. Int64.to_float scaled_saving) in
        if verbose then
          printf "estimate_target_size: %s: %Ld [%s]\n%!"
            ov.ov_sd estimated_size (human_size estimated_size);
        { t with target_estimated_size = Some estimated_size }
    ) targets in

    targets
  )

(* Update the target_actual_size field in the target structure. *)
and actual_target_size target =
  { target with target_actual_size = du target.target_file }

(* There's no OCaml binding for st_blocks, so run coreutils 'du'
 * to get the used size in bytes.
 *)
and du filename =
  let cmd = sprintf "du --block-size=1 %s | awk '{print $1}'" (quote filename) in
  let lines = external_command ~prog cmd in
  (* Ignore errors because we want to avoid failures after copying. *)
  match lines with
  | line::_ -> (try Some (Int64.of_string line) with _ -> None)
  | [] -> None

let () = run_main_and_handle_errors ~prog main
