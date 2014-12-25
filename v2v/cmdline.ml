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
  let debug_overlays = ref false in
  let do_copy = ref true in
  let input_conn = ref "" in
  let input_format = ref "" in
  let machine_readable = ref false in
  let output_conn = ref "" in
  let output_format = ref "" in
  let output_name = ref "" in
  let output_storage = ref "" in
  let password_file = ref "" in
  let print_source = ref false in
  let qemu_boot = ref false in
  let quiet = ref false in
  let vdsm_vm_uuid = ref "" in
  let vdsm_ovf_output = ref "." in
  let verbose = ref false in
  let trace = ref false in
  let vmtype = ref "" in

  let input_mode = ref `Not_set in
  let set_input_mode mode =
    if !input_mode <> `Not_set then
      error (f_"%s option used more than once on the command line") "-i";
    match mode with
    | "disk" | "local" -> input_mode := `Disk
    | "libvirt" -> input_mode := `Libvirt
    | "libvirtxml" -> input_mode := `LibvirtXML
    | "ova" -> input_mode := `OVA
    | s ->
      error (f_"unknown -i option: %s") s
  in

  let network_map = ref [] in
  let add_network, add_bridge =
    let add t str =
      match string_split ":" str with
      | "", "" -> error (f_"invalid --bridge or --network parameter")
      | out, "" | "", out -> network_map := ((t, ""), out) :: !network_map
      | in_, out -> network_map := ((t, in_), out) :: !network_map
    in
    let add_network str = add Network str
    and add_bridge str = add Bridge str in
    add_network, add_bridge
  in

  let no_trim = ref [] in
  let set_no_trim = function
    | "all" | "ALL" | "*" ->
      (* Note: this is a magic value tested in the main code.  The
       * no_trim list does NOT support wildcards.
       *)
      no_trim := ["*"]
    | mps ->
      let mps = string_nsplit "," mps in
      List.iter (
        fun mp ->
          if String.length mp = 0 then
            error (f_"--no-trim: empty parameter");
          if mp.[0] <> '/' then
            error (f_"--no-trim: %s: mountpoint/device name does not begin with '/'") mp;
      ) mps;
      no_trim := mps
  in

  let output_mode = ref `Not_set in
  let set_output_mode mode =
    if !output_mode <> `Not_set then
      error (f_"%s option used more than once on the command line") "-o";
    match mode with
    | "glance" -> output_mode := `Glance
    | "libvirt" -> output_mode := `Libvirt
    | "disk" | "local" -> output_mode := `Local
    | "null" -> output_mode := `Null
    | "ovirt" | "rhev" -> output_mode := `RHEV
    | "qemu" -> output_mode := `QEmu
    | "vdsm" -> output_mode := `VDSM
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

  let vdsm_image_uuids = ref [] in
  let add_vdsm_image_uuid s = vdsm_image_uuids := s :: !vdsm_image_uuids in

  let vdsm_vol_uuids = ref [] in
  let add_vdsm_vol_uuid s = vdsm_vol_uuids := s :: !vdsm_vol_uuids in

  let i_options =
    String.concat "|" (Modules_list.input_modules ())
  and o_options =
    String.concat "|" (Modules_list.output_modules ()) in

  let ditto = " -\"-" in
  let argspec = Arg.align [
    "-b",        Arg.String add_bridge,     "in:out " ^ s_"Map bridge 'in' to 'out'";
    "--bridge",  Arg.String add_bridge,     "in:out " ^ ditto;
    "--debug-gc",Arg.Set debug_gc,          " " ^ s_"Debug GC and memory allocations";
    "--debug-overlay",Arg.Set debug_overlays,
    " " ^ s_"Save overlay files";
    "--debug-overlays",Arg.Set debug_overlays,
    ditto;
    "-i",        Arg.String set_input_mode, i_options ^ " " ^ s_"Set input mode (default: libvirt)";
    "-ic",       Arg.Set_string input_conn, "uri " ^ s_"Libvirt URI";
    "-if",       Arg.Set_string input_format,
    "format " ^ s_"Input format (for -i disk)";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-n",        Arg.String add_network,    "in:out " ^ s_"Map network 'in' to 'out'";
    "--network", Arg.String add_network,    "in:out " ^ ditto;
    "--no-copy", Arg.Clear do_copy,         " " ^ s_"Just write the metadata";
    "--no-trim", Arg.String set_no_trim,    "all|mp,mp,.." ^ " " ^ s_"Don't trim selected mounts";
    "-o",        Arg.String set_output_mode, o_options ^ " " ^ s_"Set output mode (default: libvirt)";
    "-oa",       Arg.String set_output_alloc, "sparse|preallocated " ^ s_"Set output allocation mode";
    "-oc",       Arg.Set_string output_conn, "uri " ^ s_"Libvirt URI";
    "-of",       Arg.Set_string output_format, "raw|qcow2 " ^ s_"Set output format";
    "-on",       Arg.Set_string output_name, "name " ^ s_"Rename guest when converting";
    "-os",       Arg.Set_string output_storage, "storage " ^ s_"Set output storage location";
    "--password-file", Arg.Set_string password_file, "file " ^ s_"Use password from file";
    "--print-source", Arg.Set print_source, " " ^ s_"Print source and stop";
    "--qemu-boot", Arg.Set qemu_boot,       " " ^ s_"This option cannot be used in RHEL";
    "-q",        Arg.Set quiet,             " " ^ s_"Quiet output";
    "--quiet",   Arg.Set quiet,             ditto;
    "--root",    Arg.String set_root_choice,"ask|... " ^ s_"How to choose root filesystem";
    "--vdsm-image-uuid",
    Arg.String add_vdsm_image_uuid, "uuid " ^ s_"Output image UUID(s)";
    "--vdsm-vol-uuid",
    Arg.String add_vdsm_vol_uuid, "uuid " ^ s_"Output vol UUID(s)";
    "--vdsm-vm-uuid",
    Arg.Set_string vdsm_vm_uuid, "uuid " ^ s_"Output VM UUID";
    "--vdsm-ovf-output",
    Arg.Set_string vdsm_ovf_output, " " ^ s_"Output OVF file";
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

 virt-v2v -ic vpx://vcenter.example.com/Datacenter/esxi -os imported esx_guest

 virt-v2v -ic vpx://vcenter.example.com/Datacenter/esxi esx_guest \
   -o rhev -os rhev.nfs:/export_domain --network rhevm

 virt-v2v -i libvirtxml guest-domain.xml -o local -os /var/tmp

 virt-v2v -i disk disk.img -o local -os /var/tmp

 virt-v2v -i disk disk.img -o glance

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
  let debug_overlays = !debug_overlays in
  let do_copy = !do_copy in
  let input_conn = match !input_conn with "" -> None | s -> Some s in
  let input_format = match !input_format with "" -> None | s -> Some s in
  let input_mode = !input_mode in
  let machine_readable = !machine_readable in
  let network_map = !network_map in
  let no_trim = !no_trim in
  let output_alloc = !output_alloc in
  let output_conn = match !output_conn with "" -> None | s -> Some s in
  let output_format = match !output_format with "" -> None | s -> Some s in
  let output_mode = !output_mode in
  let output_name = match !output_name with "" -> None | s -> Some s in
  let output_storage = !output_storage in
  let password_file = match !password_file with "" -> None | s -> Some s in
  let print_source = !print_source in
  let qemu_boot = !qemu_boot in
  let quiet = !quiet in
  let root_choice = !root_choice in
  let vdsm_image_uuids = List.rev !vdsm_image_uuids in
  let vdsm_vol_uuids = List.rev !vdsm_vol_uuids in
  let vdsm_vm_uuid = !vdsm_vm_uuid in
  let vdsm_ovf_output = !vdsm_ovf_output in
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
    List.iter (printf "input:%s\n") (Modules_list.input_modules ());
    List.iter (printf "output:%s\n") (Modules_list.output_modules ());
    List.iter (printf "convert:%s\n") (Modules_list.convert_modules ());
    exit 0
  );

  (* Parse out the password from the password file. *)
  let password =
    match password_file with
    | None -> None
    | Some filename ->
      let password = read_whole_file filename in
      Some password in

  (* Parsing of the argument(s) depends on the input mode. *)
  let input =
    match input_mode with
    | `Disk ->
      (* -i disk: Expecting a single argument, the disk filename. *)
      let disk =
        match args with
        | [disk] -> disk
        | _ ->
          error (f_"expecting a disk image (filename) on the command line") in
      Input_disk.input_disk verbose input_format disk

    | `Not_set
    | `Libvirt ->
      (* -i libvirt: Expecting a single argument which is the name
       * of the libvirt guest.
       *)
      let guest =
        match args with
        | [guest] -> guest
        | _ ->
          error (f_"expecting a libvirt guest name on the command line") in
      Input_libvirt.input_libvirt verbose password input_conn guest

    | `LibvirtXML ->
      (* -i libvirtxml: Expecting a filename (XML file). *)
      let filename =
        match args with
        | [filename] -> filename
        | _ ->
          error (f_"expecting a libvirt XML file name on the command line") in
      Input_libvirtxml.input_libvirtxml verbose filename

    | `OVA ->
      (* -i ova: Expecting an ova filename (tar file). *)
      let filename =
        match args with
        | [filename] -> filename
        | _ ->
          error (f_"expecting an OVA file name on the command line") in
      Input_ova.input_ova verbose filename in

  (* Parse the output mode. *)
  let output =
    match output_mode with
    | `Glance ->
      if output_conn <> None then
        error (f_"-o glance: -oc option cannot be used in this output mode");
      if output_storage <> "" then
        error (f_"-o glance: -os option cannot be used in this output mode");
      if qemu_boot then
        error (f_"-o glance: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o glance'");
      if not do_copy then
        error (f_"--no-copy and '-o glance' cannot be used at the same time");
      Output_glance.output_glance verbose

    | `Not_set
    | `Libvirt ->
      let output_storage =
        if output_storage = "" then "default" else output_storage in
      if qemu_boot then
        error (f_"-o libvirt: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o libvirt'");
      if not do_copy then
        error (f_"--no-copy and '-o libvirt' cannot be used at the same time");
      Output_libvirt.output_libvirt verbose output_conn output_storage

    | `Local ->
      if output_storage = "" then
        error (f_"-o local: output directory was not specified, use '-os /dir'");
      if not (is_directory output_storage) then
        error (f_"-os %s: output directory does not exist or is not a directory")
          output_storage;
      if qemu_boot then
        error (f_"-o local: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o local'");
      Output_local.output_local verbose output_storage

    | `Null ->
      if output_conn <> None then
        error (f_"-o null: -oc option cannot be used in this output mode");
      if output_storage <> "" then
        error (f_"-o null: -os option cannot be used in this output mode");
      if qemu_boot then
        error (f_"-o null: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o null'");
      Output_null.output_null verbose

    | `QEmu ->
      if not (is_directory output_storage) then
        error (f_"-os %s: output directory does not exist or is not a directory")
          output_storage;
      if qemu_boot then
        error (f_"-o qemu: the --qemu-boot option cannot be used in RHEL");
      Output_qemu.output_qemu verbose output_storage qemu_boot

    | `RHEV ->
      if output_storage = "" then
        error (f_"-o rhev: output storage was not specified, use '-os'");
      if qemu_boot then
        error (f_"-o rhev: --qemu-boot option cannot be used in this output mode");
      Output_rhev.output_rhev verbose output_storage vmtype output_alloc

    | `VDSM ->
      if output_storage = "" then
        error (f_"-o vdsm: output storage was not specified, use '-os'");
      if qemu_boot then
        error (f_"-o vdsm: --qemu-boot option cannot be used in this output mode");
      if vdsm_image_uuids = [] || vdsm_vol_uuids = [] || vdsm_vm_uuid = "" then
        error (f_"-o vdsm: either --vdsm-image-uuid, --vdsm-vol-uuid or --vdsm-vm-uuid was not specified");
      let vdsm_params = {
        Output_vdsm.image_uuids = vdsm_image_uuids;
        vol_uuids = vdsm_vol_uuids;
        vm_uuid = vdsm_vm_uuid;
        ovf_output = vdsm_ovf_output;
      } in
      Output_vdsm.output_vdsm verbose output_storage vdsm_params
        vmtype output_alloc in

  input, output,
  debug_gc, debug_overlays, do_copy, network_map, no_trim,
  output_alloc, output_format, output_name,
  print_source, quiet, root_choice, trace, verbose
