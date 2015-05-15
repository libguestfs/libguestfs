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

open Customize_cmdline

module G = Guestfs

open Unix
open Printf

let prog = Filename.basename Sys.executable_name

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

  let arch = ref "" in

  let attach = ref [] in
  let attach_format = ref None in
  let set_attach_format = function
    | "auto" -> attach_format := None
    | s -> attach_format := Some s
  in
  let attach_disk s = attach := (!attach_format, s) :: !attach in

  let cache = ref Paths.xdg_cache_home in
  let set_cache arg = cache := Some arg in
  let no_cache () = cache := None in

  let check_signature = ref true in
  let curl = ref "curl" in

  let delete_on_failure = ref true in

  let fingerprints = ref [] in
  let add_fingerprint arg = fingerprints := arg :: !fingerprints in

  let format = ref "" in
  let gpg = ref "gpg" in

  let list_format = ref `Short in
  let list_set_long () = list_format := `Long in
  let list_set_format arg =
    list_format := match arg with
    | "short" -> `Short
    | "long" -> `Long
    | "json" -> `Json
    | fmt ->
      eprintf (f_"%s: invalid --list-format type '%s', see the man page.\n") prog fmt;
      exit 1 in

  let machine_readable = ref false in

  let memsize = ref None in
  let set_memsize arg = memsize := Some arg in

  let network = ref true in
  let output = ref "" in

  let quiet = ref false in

  let size = ref None in
  let set_size arg = size := Some (parse_size ~prog arg) in

  let smp = ref None in
  let set_smp arg = smp := Some arg in

  let sources = ref [] in
  let add_source arg = sources := arg :: !sources in

  let sync = ref true in
  let trace = ref false in
  let verbose = ref false in

  let argspec = [
    "--arch",    Arg.Set_string arch,       "arch" ^ " " ^ s_"Set the output architecture";
    "--attach",  Arg.String attach_disk,    "iso" ^ " " ^ s_"Attach data disk/ISO during install";
    "--attach-format",  Arg.String set_attach_format,
                                            "format" ^ " " ^ s_"Set attach disk format";
    "--cache",   Arg.String set_cache,      "dir" ^ " " ^ s_"Set template cache dir";
    "--no-cache", Arg.Unit no_cache,        " " ^ s_"Disable template cache";
    "--cache-all-templates", Arg.Unit cache_all_mode,
                                            " " ^ s_"Download all templates to the cache";
    "--check-signature", Arg.Set check_signature,
                                            " " ^ s_"Check digital signatures";
    "--check-signatures", Arg.Set check_signature,
                                            " " ^ s_"Check digital signatures";
    "--no-check-signature", Arg.Clear check_signature,
                                            " " ^ s_"Disable digital signatures";
    "--no-check-signatures", Arg.Clear check_signature,
                                            " " ^ s_"Disable digital signatures";
    "--curl",    Arg.Set_string curl,       "curl" ^ " " ^ s_"Set curl binary/command";
    "--delete-cache", Arg.Unit delete_cache_mode,
                                            " " ^ s_"Delete the template cache";
    "--no-delete-on-failure", Arg.Clear delete_on_failure,
                                            " " ^ s_"Don't delete output file on failure";
    "--fingerprint", Arg.String add_fingerprint,
                                            "AAAA.." ^ " " ^ s_"Fingerprint of valid signing key";
    "--format",  Arg.Set_string format,     "raw|qcow2" ^ " " ^ s_"Output format (default: raw)";
    "--get-kernel", Arg.Unit get_kernel_mode,
                                            "image" ^ " " ^ s_"Get kernel from image";
    "--gpg",    Arg.Set_string gpg,         "gpg" ^ " " ^ s_"Set GPG binary/command";
    "-l",        Arg.Unit list_mode,        " " ^ s_"List available templates";
    "--list",    Arg.Unit list_mode,        " " ^ s_"List available templates";
    "--long",    Arg.Unit list_set_long,    " " ^ s_"Shortcut for --list-format short";
    "--list-format", Arg.String list_set_format,
                                            "short|long|json" ^ " " ^ s_"Set the format for --list (default: short)";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-m",        Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--memsize", Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--network", Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "--notes",   Arg.Unit notes_mode,       " " ^ s_"Display installation notes";
    "-o",        Arg.Set_string output,     "file" ^ " " ^ s_"Set output filename";
    "--output",  Arg.Set_string output,     "file" ^ " " ^ s_"Set output filename";
    "--print-cache", Arg.Unit print_cache_mode,
                                            " " ^ s_"Print info about template cache";
    "--quiet",   Arg.Set quiet,             " " ^ s_"No progress messages";
    "--size",    Arg.String set_size,       "size" ^ " " ^ s_"Set output disk size";
    "--smp",     Arg.Int set_smp,           "vcpus" ^ " " ^ s_"Set number of vCPUs";
    "--source",  Arg.String add_source,     "URL" ^ " " ^ s_"Set source URL";
    "--no-sync", Arg.Clear sync,            " " ^ s_"Do not fsync output file on exit";
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
  let arch = !arch in
  let attach = List.rev !attach in
  let cache = !cache in
  let check_signature = !check_signature in
  let curl = !curl in
  let delete_on_failure = !delete_on_failure in
  let fingerprints = List.rev !fingerprints in
  let format = match !format with "" -> None | s -> Some s in
  let gpg = !gpg in
  let list_format = !list_format in
  let machine_readable = !machine_readable in
  let memsize = !memsize in
  let network = !network in
  let ops = get_customize_ops () in
  let output = match !output with "" -> None | s -> Some s in
  let quiet = !quiet in
  let size = !size in
  let smp = !smp in
  let sources = List.rev !sources in
  let sync = !sync in
  let trace = !trace in
  let verbose = !verbose in

  (* No arguments and machine-readable mode?  Print some facts. *)
  if args = [] && machine_readable then (
    printf "virt-builder\n";
    printf "arch\n";
    printf "config-file\n";
    printf "customize\n";
    printf "json-list\n";
    if Pxzcat.using_parallel_xzcat () then printf "pxzcat\n";
    exit 0
  );

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
      if format <> None then (
        eprintf (f_"%s: virt-builder --list: use '--list-format', not '--format'.\n") prog;
        exit 1
      );
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

  (* Check source(s) and fingerprint(s). *)
  let sources =
    let rec repeat x = function
      | 0 -> [] | 1 -> [x]
      | n -> x :: repeat x (n-1)
    in

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

    (* Combine the sources and fingerprints into a single list of pairs. *)
    List.combine sources fingerprints in

  (* Check the architecture. *)
  let arch =
    match arch with
    | "" -> Config.host_cpu
    | arch -> arch in

  (* If user didn't elect any root password, that means we set a random
   * root password.
   *)
  let ops =
    let has_set_root_password = List.exists (
      function `RootPassword _ -> true | _ -> false
    ) ops.ops in
    if has_set_root_password then ops
    else (
      let pw = Password.parse_selector ~prog "random" in
      { ops with ops = ops.ops @ [ `RootPassword pw ] }
    ) in

  mode, arg,
  arch, attach, cache, check_signature, curl,
  delete_on_failure, format, gpg, list_format, memsize,
  network, ops, output, quiet, size, smp, sources, sync,
  trace, verbose
