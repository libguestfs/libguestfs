(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

(* Command line argument parsing. *)

open Common_gettext.Gettext
open Common_utils

module G = Guestfs

open Password

open Unix
open Printf

let prog = Filename.basename Sys.executable_name

let default_cachedir =
  try Some (Sys.getenv "XDG_CACHE_HOME" // "virt-builder")
  with Not_found ->
    try Some (Sys.getenv "HOME" // ".cache" // "virt-builder")
    with Not_found ->
      None (* no cache directory *)

let default_source = "http://libguestfs.org/download/builder/index.asc"

let parse_cmdline () =
  let display_version () =
    printf "virt-builder %s\n" Config.package_version;
    exit 0
  in

  let mode = ref `Install in
  let list_mode () = mode := `List in
  let notes_mode () = mode := `Notes in
  let get_kernel_mode () = mode := `Get_kernel in
  let cache_all_mode () = mode := `Cache_all in
  let print_cache_mode () = mode := `Print_cache in
  let delete_cache_mode () = mode := `Delete_cache in

  let attach = ref [] in
  let attach_format = ref None in
  let set_attach_format = function
    | "auto" -> attach_format := None
    | s -> attach_format := Some s
  in
  let attach_disk s = attach := (!attach_format, s) :: !attach in

  let cache = ref default_cachedir in
  let set_cache arg = cache := Some arg in
  let no_cache () = cache := None in

  let check_signature = ref true in
  let curl = ref "curl" in
  let debug = ref false in

  let delete = ref [] in
  let add_delete s = delete := s :: !delete in

  let edit = ref [] in
  let add_edit arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        eprintf (f_"%s: invalid --edit format, see the man page.\n") prog;
        exit 1 in
    let len = String.length arg in
    let file = String.sub arg 0 i in
    let expr = String.sub arg (i+1) (len-(i+1)) in
    edit := (file, expr) :: !edit
  in

  let fingerprints = ref [] in
  let add_fingerprint arg = fingerprints := arg :: !fingerprints in

  let firstboot = ref [] in
  let add_firstboot s =
    if not (Sys.file_exists s) then (
      if not (String.contains s ' ') then
        eprintf (f_"%s: %s: %s: file not found\n") prog "--firstboot" s
      else
        eprintf (f_"%s: %s: %s: file not found [did you mean %s?]\n") prog "--firstboot" s "--firstboot-command";
      exit 1
    );
    firstboot := `Script s :: !firstboot
  in
  let add_firstboot_cmd s = firstboot := `Command s :: !firstboot in
  let add_firstboot_install pkgs =
    let pkgs = string_nsplit "," pkgs in
    firstboot := `Packages pkgs :: !firstboot
  in

  let format = ref "" in
  let gpg = ref "gpg" in

  let hostname = ref None in
  let set_hostname s = hostname := Some s in

  let install = ref [] in
  let add_install pkgs =
    let pkgs = string_nsplit "," pkgs in
    install := pkgs @ !install
  in

  let list_long = ref false in

  let memsize = ref None in
  let set_memsize arg = memsize := Some arg in

  let mkdirs = ref [] in
  let add_mkdir arg = mkdirs := arg :: !mkdirs in

  let network = ref true in
  let output = ref "" in

  let password_crypto : password_crypto option ref = ref None in
  let set_password_crypto arg =
    password_crypto := Some (password_crypto_of_string ~prog arg)
  in

  let quiet = ref false in

  let root_password = ref None in
  let set_root_password arg =
    let pw = parse_selector ~prog arg in
    root_password := Some pw
  in

  let run = ref [] in
  let add_run s =
    if not (Sys.file_exists s) then (
      if not (String.contains s ' ') then
        eprintf (f_"%s: %s: %s: file not found\n") prog "--run" s
      else
        eprintf (f_"%s: %s: %s: file not found [did you mean %s?]\n") prog "--run" s "--run-command";
      exit 1
    );
    run := `Script s :: !run
  in
  let add_run_cmd s = run := `Command s :: !run in

  let scrub = ref [] in
  let add_scrub s = scrub := s :: !scrub in

  let scrub_logfile = ref false in

  let size = ref None in
  let set_size arg = size := Some (parse_size ~prog arg) in

  let smp = ref None in
  let set_smp arg = smp := Some arg in

  let sources = ref [] in
  let add_source arg = sources := arg :: !sources in

  let sync = ref true in

  let upload = ref [] in
  let add_upload arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        eprintf (f_"%s: invalid --upload format, see the man page.\n") prog;
        exit 1 in
    let len = String.length arg in
    let file = String.sub arg 0 i in
    if not (Sys.file_exists file) then (
      eprintf (f_"%s: --upload: %s: file not found\n") prog file;
      exit 1
    );
    let dest = String.sub arg (i+1) (len-(i+1)) in
    upload := (file, dest) :: !upload
  in

  let writes = ref [] in
  let add_write arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        eprintf (f_"%s: invalid --write format, see the man page.\n") prog;
        exit 1 in
    let len = String.length arg in
    let file = String.sub arg 0 i in
    let content = String.sub arg (i+1) (len-(i+1)) in
    writes := (file, content) :: !writes
  in

  let ditto = " -\"-" in
  let argspec = Arg.align [
    "--attach",  Arg.String attach_disk,    "iso" ^ " " ^ s_"Attach data disk/ISO during install";
    "--attach-format",  Arg.String set_attach_format,
                                            "format" ^ " " ^ s_"Set attach disk format";
    "--cache",   Arg.String set_cache,      "dir" ^ " " ^ s_"Set template cache dir";
    "--no-cache", Arg.Unit no_cache,        " " ^ s_"Disable template cache";
    "--cache-all-templates", Arg.Unit cache_all_mode,
                                            " " ^ s_"Download all templates to the cache";
    "--check-signature", Arg.Set check_signature,
                                            " " ^ s_"Check digital signatures";
    "--check-signatures", Arg.Set check_signature, ditto;
    "--no-check-signature", Arg.Clear check_signature,
                                            " " ^ s_"Disable digital signatures";
    "--no-check-signatures", Arg.Clear check_signature, ditto;
    "--curl",    Arg.Set_string curl,       "curl" ^ " " ^ s_"Set curl binary/command";
    "--delete",  Arg.String add_delete,     "name" ^ " " ^ s_"Delete a file or dir";
    "--delete-cache", Arg.Unit delete_cache_mode,
                                            " " ^ s_"Delete the template cache";
    "--edit",    Arg.String add_edit,       "file:expr" ^ " " ^ s_"Edit file with Perl expr";
    "--fingerprint", Arg.String add_fingerprint,
                                            "AAAA.." ^ " " ^ s_"Fingerprint of valid signing key";
    "--firstboot", Arg.String add_firstboot, "script" ^ " " ^ s_"Run script at first guest boot";
    "--firstboot-command", Arg.String add_firstboot_cmd, "cmd+args" ^ " " ^ s_"Run command at first guest boot";
    "--firstboot-install", Arg.String add_firstboot_install,
                                            "pkg,pkg" ^ " " ^ s_"Add package(s) to install at firstboot";
    "--format",  Arg.Set_string format,     "raw|qcow2" ^ " " ^ s_"Output format (default: raw)";
    "--get-kernel", Arg.Unit get_kernel_mode,
                                            "image" ^ " " ^ s_"Get kernel from image";
    "--gpg",    Arg.Set_string gpg,         "gpg" ^ " " ^ s_"Set GPG binary/command";
    "--hostname", Arg.String set_hostname,  "hostname" ^ " " ^ s_"Set the hostname";
    "--install", Arg.String add_install,    "pkg,pkg" ^ " " ^ s_"Add package(s) to install";
    "-l",        Arg.Unit list_mode,        " " ^ s_"List available templates";
    "--list",    Arg.Unit list_mode,        ditto;
    "--long",    Arg.Set list_long,         ditto;
    "--no-logfile", Arg.Set scrub_logfile,  " " ^ s_"Scrub build log file";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "-m",        Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--memsize", Arg.Int set_memsize,       "mb" ^ ditto;
    "--mkdir",   Arg.String add_mkdir,      "dir" ^ " " ^ s_"Create directory";
    "--network", Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "--notes",   Arg.Unit notes_mode,       " " ^ s_"Display installation notes";
    "-o",        Arg.Set_string output,     "file" ^ " " ^ s_"Set output filename";
    "--output",  Arg.Set_string output,     "file" ^ ditto;
    "--password-crypto", Arg.String set_password_crypto,
                                            "md5|sha256|sha512" ^ " " ^ s_"Set password crypto";
    "--print-cache", Arg.Unit print_cache_mode,
                                            " " ^ s_"Print info about template cache";
    "--quiet",   Arg.Set quiet,             " " ^ s_"No progress messages";
    "--root-password", Arg.String set_root_password,
                                            "..." ^ " " ^ s_"Set root password";
    "--run",     Arg.String add_run,        "script" ^ " " ^ s_"Run script in disk image";
    "--run-command", Arg.String add_run_cmd, "cmd+args" ^ " " ^ s_"Run command in disk image";
    "--scrub",   Arg.String add_scrub,      "name" ^ " " ^ s_"Scrub a file";
    "--size",    Arg.String set_size,       "size" ^ " " ^ s_"Set output disk size";
    "--smp",     Arg.Int set_smp,           "vcpus" ^ " " ^ s_"Set number of vCPUs";
    "--source",  Arg.String add_source,     "URL" ^ " " ^ s_"Set source URL";
    "--no-sync", Arg.Clear sync,            " " ^ s_"Do not fsync output file on exit";
    "--upload",  Arg.String add_upload,     "file:dest" ^ " " ^ s_"Upload file to dest";
    "-v",        Arg.Set debug,             " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set debug,             ditto;
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  ditto;
    "--write",   Arg.String add_write,      "file:content" ^ " " ^ s_"Write file";
  ] in
  long_options := argspec;

  let args = ref [] in
  let anon_fun s = args := s :: !args in
  let usage_msg =
    sprintf (f_"\
%s: build virtual machine images quickly

 virt-builder OS-VERSION
 virt-builder -l
 virt-builder --notes OS-VERSION
 virt-builder --print-cache
 virt-builder --cache-all-templates
 virt-builder --delete-cache
 virt-builder --get-kernel IMAGE

A short summary of the options is given below.  For detailed help please
read the man page virt-builder(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference options. *)
  let args = List.rev !args in
  let mode = !mode in
  let attach = List.rev !attach in
  let cache = !cache in
  let check_signature = !check_signature in
  let curl = !curl in
  let debug = !debug in
  let delete = List.rev !delete in
  let edit = List.rev !edit in
  let fingerprints = List.rev !fingerprints in
  let firstboot = List.rev !firstboot in
  let run = List.rev !run in
  let format = match !format with "" -> None | s -> Some s in
  let gpg = !gpg in
  let hostname = !hostname in
  let install = !install in
  let list_long = !list_long in
  let memsize = !memsize in
  let mkdirs = List.rev !mkdirs in
  let network = !network in
  let output = match !output with "" -> None | s -> Some s in
  let password_crypto = !password_crypto in
  let quiet = !quiet in
  let root_password = !root_password in
  let scrub = List.rev !scrub in
  let scrub_logfile = !scrub_logfile in
  let size = !size in
  let smp = !smp in
  let sources = List.rev !sources in
  let sync = !sync in
  let upload = List.rev !upload in
  let writes = List.rev !writes in

  (* Check options. *)
  let arg =
    match mode with
    | `Install ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder os-version\nMissing 'os-version'. Use '--list' to list available template names.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder: too many parameters, expecting 'os-version'\n") prog;
        exit 1
      )
    | `List ->
      (match args with
      | [] -> ""
      | _ ->
        eprintf (f_"%s: virt-builder --list does not need any extra arguments.\n") prog;
        exit 1
      )
    | `Notes ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder --notes os-version\nMissing 'os-version'. Use '--list' to list available template names.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder: too many parameters, expecting 'os-version'\n") prog;
        exit 1
      )
    | `Cache_all
    | `Print_cache
    | `Delete_cache ->
      (match args with
      | [] -> ""
      | _ ->
        eprintf (f_"%s: virt-builder --cache-all-templates/--print-cache/--delete-cache does not need any extra arguments.\n") prog;
        exit 1
      )
    | `Get_kernel ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder --get-kernel image\nMissing 'image' (disk image file) argument.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder --get-kernel: too many parameters\n") prog;
        exit 1
      ) in

  (* Check source(s) and fingerprint(s), or use environment or default. *)
  let sources =
    let list_split = function "" -> [] | str -> string_nsplit "," str in
    let rec repeat x = function
      | 0 -> [] | 1 -> [x]
      | n -> x :: repeat x (n-1)
    in

    let sources =
      if sources <> [] then sources
      else (
        try list_split (Sys.getenv "VIRT_BUILDER_SOURCE")
        with Not_found -> [ default_source ]
      ) in
    let fingerprints =
      if fingerprints <> [] then fingerprints
      else (
        try list_split (Sys.getenv "VIRT_BUILDER_FINGERPRINT")
        with Not_found -> [ Sigchecker.default_fingerprint ]
      ) in

    let nr_sources = List.length sources in
    let fingerprints =
      match fingerprints with
      | [fingerprint] ->
        (* You're allowed to have multiple sources and one fingerprint: it
         * means that the same fingerprint is used for all sources.
         *)
        repeat fingerprint nr_sources
      | xs -> xs in

    if List.length fingerprints <> nr_sources then (
      eprintf (f_"%s: source and fingerprint lists are not the same length\n")
        prog;
      exit 1
    );

    assert (nr_sources > 0);

    (* Combine the sources and fingerprints into a single list of pairs. *)
    List.combine sources fingerprints in

  mode, arg,
  attach, cache, check_signature, curl, debug, delete, edit,
  firstboot, run, format, gpg, hostname, install, list_long, memsize, mkdirs,
  network, output, password_crypto, quiet, root_password, scrub,
  scrub_logfile, size, smp, sources, sync, upload, writes
