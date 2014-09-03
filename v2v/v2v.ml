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

let () = Random.self_init ()

let rec main () =
  (* Handle the command line. *)
  let input, output,
    debug_gc, do_copy, network_map,
    output_alloc, output_format, output_name,
    print_source, quiet, root_choice, trace, verbose =
    Cmdline.parse_cmdline () in

  let msg fs = make_message_function ~quiet fs in

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
  let overlays =
    List.map (
      fun ({ s_qemu_uri = qemu_uri; s_format = format } as source) ->
        let overlay_file = Filename.temp_file "v2vovl" ".qcow2" in
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
            error (f_"disk %s (%s) has no defined format, you have to either define the original format in the source metadata, or use the '-of' option to force the output format") ov.ov_sd ov.ov_source.s_qemu_uri in

        (* What really happens here is that the call to #disk_create
         * below fails if the format is not raw or qcow2.  We would
         * have to extend libguestfs to support further formats, which
         * is trivial, but we'd want to check that the files being
         * created by qemu-img really work.  In any case, fail here,
         * early, not below, later.
         *)
        if format <> "raw" && format <> "qcow2" then
          error (f_"output format should be 'raw' or 'qcow2'.\n\nUse the '-of <format>' option to select a different output format for the converted guest.\n\nOther output formats are not supported at the moment, although might be considered in future.");

        (* output#prepare_targets will fill in the target_file field. *)
        { target_file = ""; target_format = format; target_overlay = ov }
    ) overlays in
  let targets = output#prepare_targets source targets in

  (* Inspection - this also mounts up the filesystems. *)
  msg (f_"Inspecting the overlay");
  let inspect = inspect_source g root_choice in

  (* Conversion. *)
  let guestcaps =
    (match inspect.i_product_name with
    | "unknown" ->
      msg (f_"Converting the guest to run on KVM")
    | prod ->
      msg (f_"Converting %s to run on KVM") prod
    );

    match inspect.i_type, inspect.i_distro with
    | "linux", ("fedora"
                   | "rhel" | "centos" | "scientificlinux" | "redhat-based"
                   | "sles" | "suse-based" | "opensuse") ->
        (* RHEV doesn't support serial console so remove any on conversion. *)
        let keep_serial_console = output#keep_serial_console in
        Convert_linux.convert ~keep_serial_console verbose g inspect source

    | "windows", _ -> Convert_windows.convert verbose g inspect source

    | typ, distro ->
      error (f_"virt-v2v is unable to convert this guest type (%s/%s)")
        typ distro in

  if do_copy then (
    (* Doing fstrim on all the filesystems reduces the transfer size
     * because unused blocks are marked in the overlay and thus do
     * not have to be copied.
     *)
    msg (f_"Mapping filesystem data to avoid copying unused and blank areas");
    let mps = g#mountpoints () in
    List.iter (
      fun (_, mp) ->
        try g#fstrim mp
        with G.Error msg -> warning ~prog (f_"%s: %s (ignored)") mp msg
    ) mps
  );

  msg (f_"Closing the overlay");
  g#umount_all ();
  g#shutdown ();
  g#close ();

  let delete_target_on_exit = ref true in

  if do_copy then (
    (* Copy the source to the output. *)
    at_exit (fun () ->
      if !delete_target_on_exit then (
        List.iter (
          fun t -> try Unix.unlink t.target_file with _ -> ()
        ) targets
      )
    );
    let nr_disks = List.length targets in
    iteri (
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

        (* It turns out that libguestfs's disk creation code is
         * considerably more flexible and easier to use than qemu-img, so
         * create the disk explicitly using libguestfs then pass the
         * 'qemu-img convert -n' option so qemu reuses the disk.
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
        (new G.guestfs ())#disk_create
          t.target_file t.target_format t.target_overlay.ov_virtual_size
          ?preallocation ?compat;

        let cmd =
          sprintf "qemu-img convert%s -n -f qcow2 -O %s %s %s"
            (if not quiet then " -p" else "")
            (quote t.target_format) (quote overlay_file)
            (quote t.target_file) in
        if verbose then printf "%s\n%!" cmd;
        if Sys.command cmd <> 0 then
          error (f_"qemu-img command failed, see earlier errors");
    ) targets
  ) (* do_copy *);

  (* Create output metadata. *)
  msg (f_"Creating output metadata");
  output#create_metadata source targets guestcaps inspect;

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
        printf (f_"dual- or multi-boot operating system detected. Choose the root filesystem\nthat contains the main operating system from the list below:\n");
        printf "\n";
        iteri (
          fun i root ->
            let prod = g#inspect_get_product_name root in
            match prod with
            | "unknown" -> printf " [%d] %s\n" i root
            | prod -> printf " [%d] %s (%s)\n" i root prod
        ) roots;
        printf "\n";
        let i = ref 0 in
        let n = List.length roots in
        while !i < 1 || !i > n do
          printf (f_"Enter number between 1 and %d: ") n;
          (try i := int_of_string (read_line ())
           with
           | End_of_file -> error (f_"connection closed")
           | Failure "int_of_string" -> ()
          )
        done;
        List.nth roots (!i - 1)

      | `Single ->
        error (f_"multi-boot operating systems are not supported by virt-v2v. Use the --root option to change how virt-v2v handles this.")

      | `First ->
        List.hd roots

      | `Dev dev ->
        if List.mem dev roots then dev
        else
          error (f_"root device %s not found.  Roots found were: %s")
            dev (String.concat " " roots) in

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
      with G.Error msg -> eprintf "%s (ignored)\n" msg
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
    i_apps = apps;
    i_apps_map = apps_map; }

let () = run_main_and_handle_errors ~prog main
