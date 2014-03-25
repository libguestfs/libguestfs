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

open Printf

module G = Guestfs

let () = Random.self_init ()

let prog = Filename.basename Sys.executable_name

let main () =
  let debug_gc = ref false in
  let domain = ref None in
  let dryrun = ref false in
  let files = ref [] in
  let format = ref "auto" in
  let quiet = ref false in
  let libvirturi = ref "" in
  let trace = ref false in
  let verbose = ref false in

  let display_version () =
    printf "virt-customize %s\n" Config.package_version;
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
  in

  let argspec = [
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
    "--format",  Arg.Set_string format,     s_"format" ^ " " ^ s_"Set format (default: auto)";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "-q",        Arg.Set quiet,             " " ^ s_"Don't print log messages";
    "--quiet",   Arg.Set quiet,             " " ^ s_"Don't print log messages";
    "-v",        Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "-x",        Arg.Set trace,             " " ^ s_"Enable tracing of libguestfs calls";
  ] in
  let customize_argspec, get_customize_ops =
    Customize_cmdline.argspec ~prog () in
  let customize_argspec =
    List.map (fun (spec, _, _) -> spec) customize_argspec in
  let argspec = argspec @ customize_argspec in
  let argspec =
    let cmp (arg1, _, _) (arg2, _, _) =
      let arg1 = skip_dashes arg1 and arg2 = skip_dashes arg2 in
      compare (String.lowercase arg1) (String.lowercase arg2)
    in
    List.sort cmp argspec in
  let argspec = Arg.align argspec in
  long_options := argspec;

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

  (* Check -a and -d options. *)
  let files = !files in
  let domain = !domain in
  let libvirturi = match !libvirturi with "" -> None | s -> Some s in
  let add =
    match files, domain with
    | [], None ->
      eprintf (f_"%s: you must give either -a or -d options\n") prog;
      eprintf (f_"Read virt-customize(1) man page for further information.\n");
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
      eprintf (f_"Read virt-customize(1) man page for further information.\n");
      exit 1
    | files, None ->
      fun g readonly ->
        List.iter (
          fun (uri, format) ->
            let { URI.path = path; protocol = protocol;
                  server = server; username = username } = uri in
            let discard = if readonly then None else Some "besteffort" in
            g#add_drive
              ~readonly ?discard
              ?format ~protocol ?server ?username
              path
        ) files
  in

  (* Dereference the rest of the args. *)
  let debug_gc = !debug_gc in
  let dryrun = !dryrun in
  let quiet = !quiet in
  let trace = !trace in
  let verbose = !verbose in

  let ops = get_customize_ops () in

  let msg fs = make_message_function ~quiet fs in

  msg (f_"Examining the guest ...");

  (* Connect to libguestfs. *)
  let g = new G.guestfs () in
  if trace then g#set_trace true;
  if verbose then g#set_verbose true;
  add g dryrun;
  g#launch ();

  (* Inspection. *)
  (match Array.to_list (g#inspect_os ()) with
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
            try g#mount dev mp;
            with Guestfs.Error msg -> eprintf (f_"%s (ignored)\n") msg
        ) mps;

        (* Do the customization. *)
        Customize_run.run ~prog ~debug:verbose ~quiet g root ops;

        g#umount_all ();
    ) roots;
  );

  g#shutdown ();
  g#close ();

  if debug_gc then
    Gc.compact ()

(* Finished. *)
let () =
  (try main ()
   with
   | Failure msg ->                     (* from failwith/failwithf *)
     eprintf (f_"%s: %s\n") prog msg;
     exit 1
   | Invalid_argument msg ->            (* probably should never happen *)
     eprintf (f_"%s: internal error: invalid argument: %s\n") prog msg;
     exit 1
   | Assert_failure (file, line, char) -> (* should never happen *)
     eprintf (f_"%s: internal error: assertion failed at %s, line %d, char %d\n")
       prog file line char;
     exit 1
   | Not_found ->                       (* should never happen *)
     eprintf (f_"%s: internal error: Not_found exception was thrown\n") prog;
     exit 1
   | exn ->
     eprintf (f_"%s: exception: %s\n") prog (Printexc.to_string exn);
     exit 1
  );

  exit 0
