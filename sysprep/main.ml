(* virt-sysprep
 * Copyright (C) 2012-2014 Red Hat Inc.
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

open Common_utils

module G = Guestfs

(* Finalize the list of operations modules. *)
let () = Sysprep_operation.bake ()

(* Command line argument parsing. *)
let prog = Filename.basename Sys.executable_name

let () = Random.self_init ()

let debug_gc, operations, g, quiet, mount_opts, verbose =
  let debug_gc = ref false in
  let domain = ref None in
  let dryrun = ref false in
  let files = ref [] in
  let format = ref "auto" in
  let quiet = ref false in
  let libvirturi = ref "" in
  let operations = ref None in
  let trace = ref false in
  let verbose = ref false in
  let mount_opts = ref "" in

  let display_version () =
    printf "virt-sysprep %s\n" Config.package_version;
    exit 0
  and add_file arg =
    let uri =
      try URI.parse_uri arg
      with Invalid_argument "URI.parse_uri" ->
        eprintf "Error parsing URI '%s'. Look for error messages printed above.\n" arg;
        exit 1 in
    let format = match !format with "auto" -> None | fmt -> Some fmt in
    files := (uri, format) :: !files
  and set_domain dom =
    if !domain <> None then (
      eprintf (f_"%s: --domain option can only be given once\n") prog;
      exit 1
    );
    domain := Some dom
  and dump_pod () =
    Sysprep_operation.dump_pod ();
    exit 0
  and dump_pod_options () =
    Sysprep_operation.dump_pod_options ();
    exit 0
  and set_enable ops =
    if !operations <> None then (
      eprintf (f_"%s: --enable option can only be given once\n") prog;
      exit 1
    );
    if ops = "" then (
      eprintf (f_"%s: you cannot pass an empty argument to --enable\n") prog;
      exit 1
    );
    let ops = string_nsplit "," ops in
    let opset = List.fold_left (
      fun opset op_name ->
        try Sysprep_operation.add_to_set op_name opset
        with Not_found ->
          eprintf (f_"%s: --enable: '%s' is not a known operation\n")
            prog op_name;
          exit 1
    ) Sysprep_operation.empty_set ops in
    operations := Some opset
  and set_operations op_string =
    let currentopset =
      match !operations with
      | Some x -> x
      | None -> Sysprep_operation.empty_set
    in
    let ops = string_nsplit "," op_string in
    let opset = List.fold_left (
      fun opset op_name ->
        let op =
          if string_prefix op_name "-" then
            `Remove (String.sub op_name 1 (String.length op_name - 1))
          else
            `Add op_name in
        match op with
        | `Add "" | `Remove "" ->
          eprintf (f_"%s: --operations: empty operation name\n")
            prog;
          exit 1
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
            eprintf (f_"%s: --operations: '%s' is not a known operation\n")
              prog n;
            exit 1
    ) currentopset ops in
    operations := Some opset
  and list_operations () =
    Sysprep_operation.list_operations ();
    exit 0
  in

  let basic_args = [
    "-a",        Arg.String add_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "--add",     Arg.String add_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "-c",        Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "--connect", Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "--debug-gc", Arg.Set debug_gc,         " " ^ s_"Debug GC and memory allocations (internal)";
    "-d",        Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "--domain",  Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "-n",        Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--dryrun",  Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--dry-run", Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--dump-pod", Arg.Unit dump_pod,        " " ^ s_"Dump POD (internal)";
    "--dump-pod-options", Arg.Unit dump_pod_options, " " ^ s_"Dump POD for options (internal)";
    "--enable",  Arg.String set_enable,     s_"operations" ^ " " ^ s_"Enable specific operations";
    "--format",  Arg.Set_string format,     s_"format" ^ " " ^ s_"Set format (default: auto)";
    "--list-operations", Arg.Unit list_operations, " " ^ s_"List supported operations";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--mount-options", Arg.Set_string mount_opts, s_"opts" ^ " " ^ s_"Set mount options (eg /:noatime;/var:rw,noatime)";
    "--operation",  Arg.String set_operations, " " ^ s_"Enable/disable specific operations";
    "--operations", Arg.String set_operations, " " ^ s_"Enable/disable specific operations";
    "-q",        Arg.Set quiet,             " " ^ s_"Don't print log messages";
    "--quiet",   Arg.Set quiet,             " " ^ s_"Don't print log messages";
    "-v",        Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "-x",        Arg.Set trace,             " " ^ s_"Enable tracing of libguestfs calls";
  ] in
  let args = basic_args @ Sysprep_operation.extra_args () in
  let args =
    List.sort (fun (a,_,_) (b,_,_) -> compare_command_line_args a b) args in
  let argspec = Arg.align args in
  long_options := argspec;
  let anon_fun _ = raise (Arg.Bad (s_"extra parameter on the command line")) in
  let usage_msg =
    sprintf (f_"\
%s: reset or unconfigure a virtual machine so clones can be made

 virt-sysprep [--options] -d domname

 virt-sysprep [--options] -a disk.img [-a disk.img ...]

A short summary of the options is given below.  For detailed help please
read the man page virt-sysprep(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Check -a and -d options. *)
  let files = !files in
  let domain = !domain in
  let libvirturi = match !libvirturi with "" -> None | s -> Some s in
  let add =
    match files, domain with
    | [], None ->
      eprintf (f_"%s: you must give either -a or -d options\n") prog;
      eprintf (f_"Read virt-sysprep(1) man page for further information.\n");
      exit 1
    | [], Some dom ->
      fun (g : Guestfs.guestfs) readonly ->
        let allowuuid = true in
        let readonlydisk = "ignore" (* ignore CDs, data drives *) in
        let discard = if readonly then None else Some "besteffort" in
        ignore (g#add_domain
                  ~readonly ?discard
                  ?libvirturi ~allowuuid ~readonlydisk
                  dom)
    | _, Some _ ->
      eprintf (f_"%s: you cannot give -a and -d options together\n") prog;
      eprintf (f_"Read virt-sysprep(1) man page for further information.\n");
      exit 1
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
  let debug_gc = !debug_gc in
  let dryrun = !dryrun in
  let operations = !operations in
  let quiet = !quiet in
  let trace = !trace in
  let verbose = !verbose in

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
    List.map (string_split ":") (string_nsplit ";" mount_opts) in
  let mount_opts mp =
    try List.assoc mp mount_opts with Not_found -> "" in

  let msg fs = make_message_function ~quiet fs in
  msg (f_"Examining the guest ...");

  (* Connect to libguestfs. *)
  let g = new G.guestfs () in
  if trace then g#set_trace true;
  if verbose then g#set_verbose true;
  add g dryrun;
  g#launch ();

  debug_gc, operations, g, quiet, mount_opts, verbose

let do_sysprep () =
  (* Inspection. *)
  match Array.to_list (g#inspect_os ()) with
  | [] ->
    eprintf (f_"%s: no operating systems were found in the guest image\n") prog;
    exit 1
  | roots ->
    List.iter (
      fun root ->
        (* Mount up the disks, like guestfish -i.
         * See [ocaml/examples/inspect_vm.ml].
         *)
        let mps = g#inspect_get_mountpoints root in
        let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
        let mps = List.sort cmp mps in
        List.iter (
          fun (mp, dev) ->
            (* Get mount options for this mountpoint. *)
            let opts = mount_opts mp in

            try g#mount_options opts dev mp;
            with Guestfs.Error msg -> eprintf (f_"%s (ignored)\n") msg
        ) mps;

        let side_effects = new Sysprep_operation.filesystem_side_effects in

        (* Perform the filesystem operations. *)
        Sysprep_operation.perform_operations_on_filesystems
          ?operations ~verbose ~quiet g root side_effects;

        (* Unmount everything in this guest. *)
        g#umount_all ();

        let side_effects = new Sysprep_operation.device_side_effects in

        (* Perform the block device operations. *)
        Sysprep_operation.perform_operations_on_devices
          ?operations ~verbose ~quiet g root side_effects;
    ) roots

(* Finished. *)
let () =
  run_main_and_handle_errors ~prog do_sysprep;
  g#shutdown ();
  g#close ();

  if debug_gc then
    Gc.compact ();

  exit 0
