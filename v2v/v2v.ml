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
    debug_gc, do_copy, output_alloc, output_format, output_name,
    quiet, root_choice, trace, verbose =
    Cmdline.parse_cmdline () in

  let msg fs = make_message_function ~quiet fs in

  let source =
    match input with
    | InputLibvirt (libvirt_uri, guest) ->
      Source_libvirt.create libvirt_uri guest
    | InputLibvirtXML filename ->
      Source_libvirt.create_from_xml filename in

  if verbose then printf "%s%!" (string_of_source source);

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
      fun { s_qemu_uri = qemu_uri; s_format = format } ->
        let overlay = Filename.temp_file "v2vovl" ".qcow2" in
        unlink_on_exit overlay;

        let options =
          "compat=1.1,lazy_refcounts=on" ^
            (match format with None -> ""
            | Some fmt -> ",backing_fmt=" ^ fmt) in
        let cmd =
          sprintf "qemu-img create -q -f qcow2 -b %s -o %s %s"
            (quote qemu_uri) (quote options) overlay in
        if verbose then printf "%s\n%!" cmd;
        if Sys.command cmd <> 0 then
          error (f_"qemu-img command failed, see earlier errors");
        overlay, qemu_uri, format
    ) source.s_disks in

  (* Open the guestfs handle. *)
  msg (f_"Opening the overlay");
  let g = new G.guestfs () in
  if trace then g#set_trace true;
  if verbose then g#set_verbose true;
  g#set_network true;
  List.iter (
    fun (overlay, _, _) ->
      g#add_drive_opts overlay
        ~format:"qcow2" ~cachemode:"unsafe" ~discard:"besteffort"
  ) overlays;

  g#launch ();

  (* Work out where we will write the final output.  Do this early
   * just so we can display errors to the user before doing too much
   * work.
   *)
  msg (f_"Initializing the target %s") (output_as_options output);
  let overlays =
    initialize_target ~verbose g
      source output output_alloc output_format output_name overlays in

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

    match inspect.i_type with
    | "linux" ->
      (match inspect.i_distro with
      | "fedora"
      | "rhel" | "centos" | "scientificlinux" | "redhat-based"
      | "sles" | "suse-based" | "opensuse" ->

        (* RHEV doesn't support serial console so remove any on conversion. *)
        let keep_serial_console =
          match output with
          | OutputRHEV _ -> Some false
          | OutputLibvirt _ | OutputLocal _ -> None in

        Convert_linux.convert ?keep_serial_console
          verbose g inspect source

      | distro ->
        error (f_"virt-v2v is unable to convert this guest type (linux/distro=%s)") distro
      );

    | "windows" -> Convert_windows.convert verbose g inspect source

    | typ ->
      error (f_"virt-v2v is unable to convert this guest type (type=%s)") typ in

  if do_copy then (
    (* Trim the filesystems to reduce transfer size. *)
    msg (f_"Trimming filesystems to reduce amount of data to copy");
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
          fun ov -> try Unix.unlink ov.ov_target_file with _ -> ()
        ) overlays
      )
    );
    let nr_overlays = List.length overlays in
    iteri (
      fun i ov ->
        msg (f_"Copying disk %d/%d to %s (%s)")
          (i+1) nr_overlays ov.ov_target_file ov.ov_target_format;
        if verbose then printf "%s%!" (string_of_overlay ov);

        (* It turns out that libguestfs's disk creation code is
         * considerably more flexible and easier to use than qemu-img, so
         * create the disk explicitly using libguestfs then pass the
         * 'qemu-img convert -n' option so qemu reuses the disk.
         *)
        let preallocation = ov.ov_preallocation in
        let compat =
          match ov.ov_target_format with "qcow2" -> Some "1.1" | _ -> None in
        (new G.guestfs ())#disk_create ov.ov_target_file
          ov.ov_target_format ov.ov_virtual_size ?preallocation ?compat;

        let cmd =
          sprintf "qemu-img convert -n -f qcow2 -O %s %s %s"
            (quote ov.ov_target_format) (quote ov.ov_overlay)
            (quote ov.ov_target_file) in
        if verbose then printf "%s\n%!" cmd;
        if Sys.command cmd <> 0 then
          error (f_"qemu-img command failed, see earlier errors");
    ) overlays
  ) (* do_copy *);

  (* Create output metadata. *)
  msg (f_"Creating output metadata");
  let () =
    (* Are we going to rename the guest? *)
    let renamed_source =
      match output_name with
      | None -> source
      | Some name -> { source with s_name = name } in
    match output with
    | OutputLibvirt (oc, os) ->
      Target_libvirt.create_metadata oc os renamed_source overlays guestcaps
    | OutputLocal dir ->
      Target_local.create_metadata dir renamed_source overlays guestcaps
    | OutputRHEV (os, rhev_params) ->
      Target_RHEV.create_metadata os rhev_params renamed_source output_alloc
        overlays inspect guestcaps in

  msg (f_"Finishing off");
  delete_target_on_exit := false;  (* Don't delete target on exit. *)

  if debug_gc then
    Gc.compact ()

and initialize_target ~verbose g
    source output output_alloc output_format output_name overlays =
  let overlays =
    mapi (
      fun i (overlay, qemu_uri, backing_format) ->
        (* Grab the virtual size of each disk. *)
        let sd = "sd" ^ drive_name i in
        let dev = "/dev/" ^ sd in
        let vsize = g#blockdev_getsize64 dev in

        (* What output format should we use? *)
        let format =
          match output_format, backing_format with
          | Some format, _ -> format    (* -of overrides everything *)
          | None, Some format -> format (* same as backing format *)
          | None, None ->
            error (f_"disk %s (%s) has no defined format, you have to either define the original format in the source metadata, or use the '-of' option to force the output format") sd qemu_uri in

        (* What output preallocation mode should we use? *)
        let preallocation =
          match format, output_alloc with
          | "raw", `Sparse -> Some "sparse"
          | "raw", `Preallocated -> Some "full"
          | "qcow2", `Sparse -> Some "off" (* ? *)
          | "qcow2", `Preallocated -> Some "metadata"
          | _ -> None (* ignore -oa flag for other formats *) in

        { ov_overlay = overlay;
          ov_target_file = "";
          ov_target_format = format;
          ov_sd = sd; ov_virtual_size = vsize; ov_preallocation = preallocation;
          ov_source_file = qemu_uri; ov_source_format = backing_format;
          ov_vol_uuid = "" }
    ) overlays in
  let overlays =
    let renamed_source =
      match output_name with
      | None -> source
      | Some name -> { source with s_name = name } in
    match output with
    | OutputLibvirt (oc, os) ->
      Target_libvirt.initialize oc os renamed_source overlays
    | OutputLocal dir -> Target_local.initialize dir renamed_source overlays
    | OutputRHEV (os, rhev_params) ->
      Target_RHEV.initialize ~verbose
        os rhev_params renamed_source output_alloc overlays in
  overlays

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

let () =
  try main ()
  with
  | Unix.Unix_error (code, fname, "") -> (* from a syscall *)
    eprintf (f_"%s: error: %s: %s\n") prog fname (Unix.error_message code);
    exit 1
  | Unix.Unix_error (code, fname, param) -> (* from a syscall *)
    eprintf (f_"%s: error: %s: %s: %s\n") prog fname (Unix.error_message code)
      param;
    exit 1
  | Sys_error msg ->                    (* from a syscall *)
    eprintf (f_"%s: error: %s\n") prog msg;
    exit 1
  | G.Error msg ->                      (* from libguestfs *)
    eprintf (f_"%s: libguestfs error: %s\n") prog msg;
    exit 1
  | Failure msg ->                      (* from failwith/failwithf *)
    eprintf (f_"%s: failure: %s\n") prog msg;
    exit 1
  | Invalid_argument msg ->             (* probably should never happen *)
    eprintf (f_"%s: internal error: invalid argument: %s\n") prog msg;
    exit 1
  | Assert_failure (file, line, char) -> (* should never happen *)
    eprintf (f_"%s: internal error: assertion failed at %s, line %d, char %d\n") prog file line char;
    exit 1
  | Not_found ->                        (* should never happen *)
    eprintf (f_"%s: internal error: Not_found exception was thrown\n") prog;
    exit 1
  | exn ->                              (* something not matched above *)
    eprintf (f_"%s: exception: %s\n") prog (Printexc.to_string exn);
    exit 1
