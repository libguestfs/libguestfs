(* virt-sysprep
 * Copyright (C) 2012-2016 Red Hat Inc.
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

open Common_utils
open Common_gettext.Gettext
open Getopt.OptionName

open Sysprep_operation

module G = Guestfs

(* Finalize the list of operations modules. *)
let () = Sysprep_operation.bake ()

(* Command line argument parsing. *)

let () = Random.self_init ()

let main () =
  let operations, g, mount_opts =
    let domain = ref None in
    let dryrun = ref false in
    let files = ref [] in
    let libvirturi = ref "" in
    let mount_opts = ref "" in
    let network = ref false in
    let operations = ref None in

    let format = ref "auto" in
    let format_consumed = ref true in
    let set_format s =
      format := s;
      format_consumed := false
    in

    let add_file arg =
      let uri =
        try URI.parse_uri arg
        with Invalid_argument "URI.parse_uri" ->
          error (f_"error parsing URI '%s'. Look for error messages printed above.") arg in
      let format = match !format with "auto" -> None | fmt -> Some fmt in
      push_front (uri, format) files;
      format_consumed := true
    and set_domain dom =
      if !domain <> None then
        error (f_"--domain option can only be given once");
      domain := Some dom
    and dump_pod () =
      Sysprep_operation.dump_pod ();
      exit 0
    and dump_pod_options () =
      Sysprep_operation.dump_pod_options ();
      exit 0
    and set_enable ops =
      if !operations <> None then
        error (f_"--enable option can only be given once");
      if ops = "" then
        error (f_"you cannot pass an empty argument to --enable");
      let ops = String.nsplit "," ops in
      let opset = List.fold_left (
        fun opset op_name ->
          try Sysprep_operation.add_to_set op_name opset
          with Not_found ->
            error (f_"--enable: '%s' is not a known operation") op_name
      ) Sysprep_operation.empty_set ops in
      operations := Some opset
    and set_operations op_string =
      let currentopset =
        match !operations with
        | Some x -> x
        | None -> Sysprep_operation.empty_set
      in
      let ops = String.nsplit "," op_string in
      let opset = List.fold_left (
        fun opset op_name ->
          let op =
            if String.is_prefix op_name "-" then
              `Remove (String.sub op_name 1 (String.length op_name - 1))
            else
              `Add op_name in
          match op with
          | `Add "" | `Remove "" ->
            error (f_"--operations: empty operation name")
          | `Add "defaults" -> Sysprep_operation.add_defaults_to_set opset
          | `Remove "defaults" -> Sysprep_operation.remove_defaults_from_set opset
          | `Add "all" -> Sysprep_operation.add_all_to_set opset
          | `Remove "all" -> Sysprep_operation.remove_all_from_set opset
          | `Add n | `Remove n ->
            let f = match op with
              | `Add n -> Sysprep_operation.add_to_set
              | `Remove n -> Sysprep_operation.remove_from_set in
            try f n opset with
            | Not_found ->
              error (f_"--operations: '%s' is not a known operation") n
      ) currentopset ops in
      operations := Some opset
    and list_operations () =
      Sysprep_operation.list_operations ();
      exit 0
    in

    let basic_args = [
      [ S 'a'; L"add" ],        Getopt.String (s_"file", add_file),        s_"Add disk image file";
      [ S 'c'; L"connect" ],        Getopt.Set_string (s_"uri", libvirturi),  s_"Set libvirt URI";
      [ S 'd'; L"domain" ],        Getopt.String (s_"domain", set_domain),      s_"Set libvirt guest name";
      [ S 'n'; L"dryrun"; L"dry-run" ],        Getopt.Set dryrun,            s_"Perform a dry run";
      [ L"dump-pod" ], Getopt.Unit dump_pod,        Getopt.hidden_option_description;
      [ L"dump-pod-options" ], Getopt.Unit dump_pod_options, Getopt.hidden_option_description;
      [ L"enable" ],  Getopt.String (s_"operations", set_enable),      s_"Enable specific operations";
      [ L"format" ],  Getopt.String (s_"format", set_format),      s_"Set format (default: auto)";
      [ L"list-operations" ], Getopt.Unit list_operations, s_"List supported operations";
      [ L"mount-options" ], Getopt.Set_string (s_"opts", mount_opts),  s_"Set mount options (eg /:noatime;/var:rw,noatime)";
      [ L"network" ], Getopt.Set network,           s_"Enable appliance network";
      [ L"no-network" ], Getopt.Clear network,      s_"Disable appliance network (default)";
      [ L"no-selinux-relabel" ], Getopt.Unit (fun () -> ()),
                                              s_"Compatibility option, does nothing";
      [ L"operation"; L"operations" ],  Getopt.String (s_"operations", set_operations), s_"Enable/disable specific operations";
    ] in
    let args = basic_args @ Sysprep_operation.extra_args () in
    let usage_msg =
      sprintf (f_"\
%s: reset or unconfigure a virtual machine so clones can be made

 virt-sysprep [--options] -d domname

 virt-sysprep [--options] -a disk.img [-a disk.img ...]

A short summary of the options is given below.  For detailed help please
read the man page virt-sysprep(1).
")
        prog in
    let opthandle = create_standard_options args usage_msg in
    Getopt.parse opthandle;

    if not !format_consumed then
      error (f_"--format parameter must appear before -a parameter");

    (* Check -a and -d options. *)
    let files = !files in
    let domain = !domain in
    let libvirturi = match !libvirturi with "" -> None | s -> Some s in
    let add =
      match files, domain with
      | [], None ->
        error (f_"you must give either -a or -d options.  Read virt-sysprep(1) man page for further information.")
      | [], Some dom ->
        fun (g : Guestfs.guestfs) readonly ->
          let allowuuid = true in
          let readonlydisk = "ignore" (* ignore CDs, data drives *) in
          let discard = if readonly then None else Some "besteffort" in
          ignore (g#add_domain
                    ~readonly ?discard
                    ?libvirturi ~allowuuid ~readonlydisk
                    dom)
      | _::_, Some _ ->
        error (f_"you cannot give -a and -d options together.  Read virt-sysprep(1) man page for further information.")
      | files, None ->
        fun g readonly ->
          List.iter (
            fun (uri, format) ->
              let { URI.path = path; protocol = protocol;
                    server = server; username = username;
                    password = password } = uri in
              let discard = if readonly then None else Some "besteffort" in
              g#add_drive
                ~readonly ?discard
                ?format ~protocol ?server ?username ?secret:password
                path
          ) files
    in

    (* Dereference the rest of the args. *)
    let dryrun = !dryrun in
    let network = !network in
    let operations = !operations in

    (* At this point we know which operations are enabled.  So call the
     * not_enabled_check_args method of all *disabled* operations, so
     * they have a chance to check for unused command line args.
     *)
    Sysprep_operation.not_enabled_check_args ?operations ();

    (* Parse the mount options string into a function that maps the
     * mountpoint to the mount options.
     *)
    let mount_opts = !mount_opts in
    let mount_opts =
      List.map (String.split ":") (String.nsplit ";" mount_opts) in
    let mount_opts mp = assoc ~default:"" mp mount_opts in

    message (f_"Examining the guest ...");

    (* Connect to libguestfs. *)
    let g = open_guestfs () in
    g#set_network network;
    add g dryrun;
    g#launch ();

    operations, g, mount_opts in

  (* Inspection. *)
  (match Array.to_list (g#inspect_os ()) with
  | [] ->
    error (f_"no operating systems were found in the guest image")
  | roots ->
    List.iter (
      fun root ->
        (* Mount up the disks, like guestfish -i.
         * See [ocaml/examples/inspect_vm.ml].
         *)
        inspect_mount_root ~mount_opts_fn:mount_opts g root;

        let side_effects = new Sysprep_operation.filesystem_side_effects in

        (* Perform the filesystem operations. *)
        Sysprep_operation.perform_operations_on_filesystems
          ?operations g root side_effects;

        (* Unmount everything in this guest. *)
        g#umount_all ();

        let side_effects = new Sysprep_operation.device_side_effects in

        (* Perform the block device operations. *)
        Sysprep_operation.perform_operations_on_devices
          ?operations g root side_effects;
    ) roots
  );

  (* Finish off. *)
  g#shutdown ();
  g#close ()

let () = run_main_and_handle_errors main
