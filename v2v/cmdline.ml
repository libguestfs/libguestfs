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

(* Command line argument parsing. *)

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

let parse_cmdline () =
  let display_version () =
    printf "virt-v2v %s\n" Config.package_version;
    exit 0
  in

  let debug_gc = ref false in
  let input_conn = ref "" in
  let output_conn = ref "" in
  let output_format = ref "" in
  let output_name = ref "" in
  let output_storage = ref "" in
  let machine_readable = ref false in
  let quiet = ref false in
  let verbose = ref false in
  let trace = ref false in
  let vmtype = ref "" in

  let input_mode = ref `Libvirt in
  let set_input_mode = function
    | "libvirt" -> input_mode := `Libvirt
    | "libvirtxml" -> input_mode := `LibvirtXML
    | s ->
      error (f_"unknown -i option: %s") s
  in

  let output_mode = ref `Libvirt in
  let set_output_mode = function
    | "libvirt" -> output_mode := `Libvirt
    | "local" -> output_mode := `Local
    | "ovirt" | "rhev" -> output_mode := `RHEV
    | s ->
      error (f_"unknown -o option: %s") s
  in

  let output_alloc = ref `Sparse in
  let set_output_alloc = function
    | "sparse" -> output_alloc := `Sparse
    | "preallocated" -> output_alloc := `Preallocated
    | s ->
      error (f_"unknown -oa option: %s") s
  in

  let root_choice = ref `Ask in
  let set_root_choice = function
    | "ask" -> root_choice := `Ask
    | "single" -> root_choice := `Single
    | "first" -> root_choice := `First
    | dev when string_prefix dev "/dev/" -> root_choice := `Dev dev
    | s ->
      error (f_"unknown --root option: %s") s
  in

  let ditto = " -\"-" in
  let argspec = Arg.align [
    "--debug-gc",Arg.Set debug_gc,          " " ^ s_"Debug GC and memory allocations";
    "-i",        Arg.String set_input_mode, "libvirtxml|libvirt " ^ s_"Set input mode (default: libvirt)";
    "-ic",       Arg.Set_string input_conn, "uri " ^ s_"Libvirt URI";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-o",        Arg.String set_output_mode, "libvirt|local|rhev " ^ s_"Set output mode (default: libvirt)";
    "-oa",       Arg.String set_output_alloc, "sparse|preallocated " ^ s_"Set output allocation mode";
    "-oc",       Arg.Set_string output_conn, "uri " ^ s_"Libvirt URI";
    "-of",       Arg.Set_string output_format, "raw|qcow2 " ^ s_"Set output format";
    "-on",       Arg.Set_string output_name, "name " ^ s_"Rename guest when converting";
    "-os",       Arg.Set_string output_storage, "storage " ^ s_"Set output storage location";
    "-q",        Arg.Set quiet,             " " ^ s_"Quiet output";
    "--quiet",   Arg.Set quiet,             ditto;
    "--root",    Arg.String set_root_choice,"ask|... " ^ s_"How to choose root filesystem";
    "-v",        Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set verbose,           ditto;
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  ditto;
    "--vmtype",  Arg.Set_string vmtype,     "server|desktop " ^ s_"Set vmtype (for RHEV)";
    "-x",        Arg.Set trace,             " " ^ s_"Enable tracing of libguestfs calls";
  ] in
  long_options := argspec;
  let args = ref [] in
  let anon_fun s = args := s :: !args in
  let usage_msg =
    sprintf (f_"\
%s: convert a guest to use KVM

 virt-v2v -ic esx://esx.example.com/ -os imported esx_guest

 virt-v2v -ic esx://esx.example.com/ \
   -o rhev -os rhev.nfs:/export_domain --network rhevm esx_guest

 virt-v2v -i libvirtxml -o local -os /tmp guest-domain.xml

There is a companion front-end called \"virt-p2v\" which comes as an
ISO or CD image that can be booted on physical machines.

A short summary of the options is given below.  For detailed help please
read the man page virt-v2v(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference the arguments. *)
  let args = List.rev !args in
  let debug_gc = !debug_gc in
  let input_conn = match !input_conn with "" -> None | s -> Some s in
  let input_mode = !input_mode in
  let machine_readable = !machine_readable in
  let output_alloc = !output_alloc in
  let output_conn = match !output_conn with "" -> None | s -> Some s in
  let output_format = match !output_format with "" -> None | s -> Some s in
  let output_mode = !output_mode in
  let output_name = match !output_name with "" -> None | s -> Some s in
  let output_storage = !output_storage in
  let quiet = !quiet in
  let root_choice = !root_choice in
  let verbose = !verbose in
  let trace = !trace in
  let vmtype =
    match !vmtype with
    | "server" -> Some `Server
    | "desktop" -> Some `Desktop
    | "" -> None
    | _ ->
      error (f_"unknown --vmtype option, must be \"server\" or \"desktop\"") in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if args = [] && machine_readable then (
    printf "virt-v2v\n";
    printf "libguestfs-rewrite\n";
    exit 0
  );

  (* Parsing of the argument(s) depends on the input mode. *)
  let input =
    match input_mode with
    | `Libvirt ->
      (* -i libvirt: Expecting a single argument which is the name
       * of the libvirt guest.
       *)
      let guest =
        match args with
        | [guest] -> guest
        | _ ->
          error (f_"expecting a libvirt guest name on the command line") in
      InputLibvirt (input_conn, guest)
    | `LibvirtXML ->
      (* -i libvirtxml: Expecting a filename (XML file). *)
      let filename =
        match args with
        | [filename] -> filename
        | _ ->
          error (f_"expecting a libvirt XML file name on the command line") in
      InputLibvirtXML filename in

  (* Parse the output mode. *)
  let output =
    match output_mode with
    | `Libvirt ->
      if output_storage <> "" then
        error (f_"-o libvirt: do not use the -os option");
      if vmtype <> None then
        error (f_"--vmtype option can only be used with '-o rhev'");
      OutputLibvirt output_conn
    | `Local ->
      if output_storage = "" then
        error (f_"-o local: output directory was not specified, use '-os /dir'");
      if not (is_directory output_storage) then
        error (f_"-os %s: output directory does not exist or is not a directory")
          output_storage;
      if vmtype <> None then
        error (f_"--vmtype option can only be used with '-o rhev'");
      OutputLocal output_storage
    | `RHEV ->
      if output_storage = "" then
        error (f_"-o rhev: output storage was not specified, use '-os'");
      OutputRHEV (output_storage, vmtype) in

  input, output,
  debug_gc, output_alloc, output_format, output_name,
  quiet, root_choice, trace, verbose
