(* virt-builder
 * Copyright (C) 2013-2016 Red Hat Inc.
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

open Utils

module G = Guestfs

open Unix
open Printf

type cmdline = {
  mode : [ `Cache_all | `Delete_cache | `Get_kernel | `Install | `List
           | `Notes | `Print_cache ];
  arg : string;
  arch : string;
  attach : (string option * string) list;
  cache : string option;
  check_signature : bool;
  curl : string;
  delete_on_failure : bool;
  format : string option;
  gpg : string;
  list_format : [`Short|`Long|`Json];
  memsize : int option;
  network : bool;
  ops : Customize_cmdline.ops;
  output : string option;
  size : int64 option;
  smp : int option;
  sources : (string * string) list;
  sync : bool;
  warn_if_partition : bool;
}

let parse_cmdline () =
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
  let attach_disk s = push_front (!attach_format, s) attach in

  let cache = ref Paths.xdg_cache_home in
  let set_cache arg = cache := Some arg in
  let no_cache () = cache := None in

  let check_signature = ref true in
  let curl = ref "curl" in

  let delete_on_failure = ref true in

  let fingerprints = ref [] in
  let add_fingerprint arg = push_front arg fingerprints in

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
      error (f_"invalid --list-format type '%s', see the man page") fmt in

  let machine_readable = ref false in

  let memsize = ref None in
  let set_memsize arg = memsize := Some arg in

  let network = ref true in
  let output = ref "" in

  let size = ref None in
  let set_size arg = size := Some (parse_size arg) in

  let smp = ref None in
  let set_smp arg = smp := Some arg in

  let sources = ref [] in
  let add_source arg = push_front arg sources in

  let sync = ref true in
  let warn_if_partition = ref true in

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
    "--long",    Arg.Unit list_set_long,    " " ^ s_"Shortcut for --list-format long";
    "--list-format", Arg.String list_set_format,
                                            "short|long|json" ^ " " ^ s_"Set the format for --list (default: short)";
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
    "--size",    Arg.String set_size,       "size" ^ " " ^ s_"Set output disk size";
    "--smp",     Arg.Int set_smp,           "vcpus" ^ " " ^ s_"Set number of vCPUs";
    "--source",  Arg.String add_source,     "URL" ^ " " ^ s_"Set source URL";
    "--no-sync", Arg.Clear sync,            " " ^ s_"Do not fsync output file on exit";
    "--no-warn-if-partition", Arg.Clear warn_if_partition,
                                            " " ^ s_"Do not warn if writing to a partition";
  ] in
  let customize_argspec, get_customize_ops = Customize_cmdline.argspec () in
  let customize_argspec =
    List.map (fun (spec, _, _) -> spec) customize_argspec in
  let argspec = argspec @ customize_argspec in
  let argspec = set_standard_options argspec in

  let args = ref [] in
  let anon_fun s = push_front s args in
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
  let size = !size in
  let smp = !smp in
  let sources = List.rev !sources in
  let sync = !sync in
  let warn_if_partition = !warn_if_partition in

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
        error (f_"virt-builder os-version\nMissing 'os-version'. Use '--list' to list available template names.")
      | _ ->
        error (f_"too many parameters, expecting 'os-version'")
      )
    | `List ->
      if format <> None then
        error (f_"--list: use '--list-format', not '--format'");
      (match args with
      | [] -> ""
      | _ ->
        error (f_"--list option does not need any extra arguments")
      )
    | `Notes ->
      (match args with
      | [arg] -> arg
      | [] ->
        error (f_"virt-builder --notes os-version\nMissing 'os-version'. Use '--list' to list available template names.")
      | _ ->
        error (f_"--notes: too many parameters, expecting 'os-version'");
      )
    | `Cache_all
    | `Print_cache
    | `Delete_cache ->
      (match args with
      | [] -> ""
      | _ ->
        error (f_"--cache-all-templates/--print-cache/--delete-cache does not need any extra arguments")
      )
    | `Get_kernel ->
      (match args with
      | [arg] -> arg
      | [] ->
        error (f_"virt-builder --get-kernel image\nMissing 'image' (disk image file) argument")
      | _ ->
        error (f_"--get-kernel: too many parameters")
      ) in

  (* Check source(s) and fingerprint(s). *)
  let sources =
    let rec repeat x = function
      | 0 -> [] | 1 -> [x]
      | n -> x :: repeat x (n-1)
    in

    let nr_sources = List.length sources in
    let fingerprints =
      if check_signature then (
        match fingerprints with
        | [fingerprint] ->
          (* You're allowed to have multiple sources and one fingerprint: it
           * means that the same fingerprint is used for all sources.
           *)
          repeat fingerprint nr_sources
        | xs -> xs
      ) else
        (* We are not checking signatures, so just ignore any fingerprint
         * specified. *)
        repeat "" nr_sources in

    if List.length fingerprints <> nr_sources then
      error (f_"source and fingerprint lists are not the same length");

    (* Combine the sources and fingerprints into a single list of pairs. *)
    List.combine sources fingerprints in

  (* Check the architecture. *)
  let arch =
    match arch with
    | "" -> Guestfs_config.host_cpu
    | arch -> arch in
  let arch = normalize_arch arch in

  (* If user didn't elect any root password, that means we set a random
   * root password.
   *)
  let ops =
    let has_set_root_password = List.exists (
      function `RootPassword _ -> true | _ -> false
    ) ops.ops in
    if has_set_root_password then ops
    else (
      let pw = Password.parse_selector "random" in
      { ops with ops = ops.ops @ [ `RootPassword pw ] }
    ) in

  { mode = mode; arg = arg;
    arch = arch; attach = attach; cache = cache;
    check_signature = check_signature; curl = curl;
    delete_on_failure = delete_on_failure; format = format;
    gpg = gpg; list_format = list_format; memsize = memsize;
    network = network; ops = ops; output = output;
    size = size; smp = smp; sources = sources; sync = sync;
    warn_if_partition = warn_if_partition;
  }
