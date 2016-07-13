(* virt-customize
 * Copyright (C) 2014 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Customize_utils
open Customize_cmdline

open Printf

module G = Guestfs

let () = Random.self_init ()

let main () =
  let attach = ref [] in
  let attach_format = ref None in
  let attach_format_consumed = ref true in
  let set_attach_format s =
    attach_format_consumed := false;
    match s with
    | "auto" -> attach_format := None
    | s -> attach_format := Some s
  in
  let attach_disk s = push_front (!attach_format, s) attach in
  let domain = ref None in
  let dryrun = ref false in
  let files = ref [] in
  let format = ref "auto" in
  let format_consumed = ref true in
  let set_format s =
    format := s;
    format_consumed := false
  in
  let libvirturi = ref "" in
  let memsize = ref None in
  let set_memsize arg = memsize := Some arg in
  let network = ref true in
  let smp = ref None in
  let set_smp arg = smp := Some arg in

  let add_file arg =
    let uri =
      try URI.parse_uri arg
      with Invalid_argument "URI.parse_uri" ->
        error (f_"error parsing URI '%s'. Look for error messages printed above.")
          arg in
    let format = match !format with "auto" -> None | fmt -> Some fmt in
    push_front (uri, format) files;
    format_consumed := true
  and set_domain dom =
    if !domain <> None then
      error (f_"--domain option can only be given once");
    domain := Some dom
  in

  let argspec = [
    "-a",        Arg.String add_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "--add",     Arg.String add_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "--attach",  Arg.String attach_disk,    "iso" ^ " " ^ s_"Attach data disk/ISO during install";
    "--attach-format",  Arg.String set_attach_format,
                                            "format" ^ " " ^ s_"Set attach disk format";
    "-c",        Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "--connect", Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "-d",        Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "--domain",  Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "-n",        Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--dryrun",  Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--dry-run", Arg.Set dryrun,            " " ^ s_"Perform a dry run";
    "--format",  Arg.String set_format,     s_"format" ^ " " ^ s_"Set format (default: auto)";
    "-m",        Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--memsize", Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--network", Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "--smp",     Arg.Int set_smp,           "vcpus" ^ " " ^ s_"Set number of vCPUs";
  ] in
  let customize_argspec, get_customize_ops =
    Customize_cmdline.argspec () in
  let customize_argspec =
    List.map (fun (spec, _, _) -> spec) customize_argspec in
  let argspec = argspec @ customize_argspec in
  let argspec = set_standard_options argspec in

  let anon_fun _ = raise (Arg.Bad (s_"extra parameter on the command line")) in
  let usage_msg =
    sprintf (f_"\
%s: customize a virtual machine

 virt-customize [--options] -d domname

 virt-customize [--options] -a disk.img [-a disk.img ...]

A short summary of the options is given below.  For detailed help please
read the man page virt-customize(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  if not !format_consumed then
    error (f_"--format parameter must appear before -a parameter");

  if not !attach_format_consumed then
    error (f_"--attach-format parameter must appear before --attach parameter");

  (* Check -a and -d options. *)
  let files = !files in
  let domain = !domain in
  let libvirturi = match !libvirturi with "" -> None | s -> Some s in
  let add =
    match files, domain with
    | [], None ->
      error (f_"you must give either -a or -d options. Read virt-customize(1) man page for further information.")
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
      error (f_"you cannot give -a and -d options together. Read virt-customize(1) man page for further information.")
    | (_::_) as files, None ->
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
  let attach = List.rev !attach in
  let dryrun = !dryrun in
  let memsize = !memsize in
  let network = !network in
  let smp = !smp in

  let ops = get_customize_ops () in

  message (f_"Examining the guest ...");

  (* Connect to libguestfs. *)
  let g =
    let g = open_guestfs () in
    may g#set_memsize memsize;
    may g#set_smp smp;
    g#set_network network;

    (* Add disks. *)
    add g dryrun;

    (* Attach ISOs, if we have any. *)
    List.iter (
      fun (format, file) ->
        g#add_drive_opts ?format ~readonly:true file;
    ) attach;

    g#launch ();
    g in

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
        let mps = g#inspect_get_mountpoints root in
        let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
        let mps = List.sort cmp mps in
        List.iter (
          fun (mp, dev) ->
            try g#mount dev mp;
            with Guestfs.Error msg -> warning (f_"%s (ignored)") msg
        ) mps;

        (* Do the customization. *)
        Customize_run.run g root ops;

        g#umount_all ();
    ) roots;
  );

  message (f_"Finishing off");
  g#shutdown ();
  g#close ()

(* Finished. *)
let () = run_main_and_handle_errors main
