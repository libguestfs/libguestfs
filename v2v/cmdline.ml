(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

module NetTypeAndName = struct
  type t = Types.vnet_type * string option
  let compare = Pervasives.compare
end
module NetworkMap = Map.Make (NetTypeAndName)

type cmdline = {
  compressed : bool;
  debug_overlays : bool;
  do_copy : bool;
  in_place : bool;
  network_map : string NetworkMap.t;
  no_trim : string list;
  output_alloc : output_allocation;
  output_format : string option;
  output_name : string option;
  print_source : bool;
  root_choice : root_choice;
}

let parse_cmdline () =
  let compressed = ref false in
  let debug_overlays = ref false in
  let do_copy = ref true in
  let machine_readable = ref false in
  let print_source = ref false in
  let qemu_boot = ref false in

  let dcpath = ref None in
  let input_conn = ref None in
  let input_format = ref None in
  let in_place = ref false in
  let output_conn = ref None in
  let output_format = ref None in
  let output_name = ref None in
  let output_storage = ref None in
  let password_file = ref None in
  let vdsm_vm_uuid = ref None in
  let vdsm_ovf_output = ref None in (* default "." *)
  let vmtype = ref None in
  let set_string_option_once optname optref arg =
    match !optref with
    | Some _ ->
       error (f_"%s option used more than once on the command line") optname
    | None ->
       optref := Some arg
  in

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

  let network_map = ref NetworkMap.empty in
  let add_network, add_bridge =
    let add flag name t str =
      match String.split ":" str with
      | "", "" ->
         error (f_"invalid %s parameter") flag
      | out, "" | "", out ->
         let key = t, None in
         if NetworkMap.mem key !network_map then
           error (f_"duplicate %s parameter.  Only one default mapping is allowed.") flag;
         network_map := NetworkMap.add key out !network_map
      | in_, out ->
         let key = t, Some in_ in
         if NetworkMap.mem key !network_map then
           error (f_"duplicate %s parameter.  Duplicate mappings specified for %s '%s'.") flag name in_;
         network_map := NetworkMap.add key out !network_map
    in
    let add_network str = add "-n/--network" (s_"network") Network str
    and add_bridge str = add "-b/--bridge" (s_"bridge") Bridge str in
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
      let mps = String.nsplit "," mps in
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

  let output_alloc = ref `Not_set in
  let set_output_alloc mode =
    if !output_alloc <> `Not_set then
      error (f_"%s option used more than once on the command line") "-oa";
    match mode with
    | "sparse" -> output_alloc := `Sparse
    | "preallocated" -> output_alloc := `Preallocated
    | s ->
      error (f_"unknown -oa option: %s") s
  in

  let root_choice = ref AskRoot in
  let set_root_choice = function
    | "ask" -> root_choice := AskRoot
    | "single" -> root_choice := SingleRoot
    | "first" -> root_choice := FirstRoot
    | dev when String.is_prefix dev "/dev/" -> root_choice := RootDev dev
    | s ->
      error (f_"unknown --root option: %s") s
  in

  let vdsm_image_uuids = ref [] in
  let add_vdsm_image_uuid s = push_front s vdsm_image_uuids in

  let vdsm_vol_uuids = ref [] in
  let add_vdsm_vol_uuid s = push_front s vdsm_vol_uuids in

  let i_options =
    String.concat "|" (Modules_list.input_modules ())
  and o_options =
    String.concat "|" (Modules_list.output_modules ()) in

  let ditto = " -\"-" in
  let argspec = [
    "-b",        Arg.String add_bridge,     "in:out " ^ s_"Map bridge 'in' to 'out'";
    "--bridge",  Arg.String add_bridge,     "in:out " ^ ditto;
    "--compressed", Arg.Set compressed,     " " ^ s_"Compress output file";
    "--dcpath",  Arg.String (set_string_option_once "--dcpath" dcpath),
                                            "path " ^ s_"Override dcPath (for vCenter)";
    "--dcPath",  Arg.String (set_string_option_once "--dcPath" dcpath),
                                            "path " ^ ditto;
    "--debug-overlay",Arg.Set debug_overlays,
    " " ^ s_"Save overlay files";
    "--debug-overlays",Arg.Set debug_overlays,
    ditto;
    "-i",        Arg.String set_input_mode, i_options ^ " " ^ s_"Set input mode (default: libvirt)";
    "-ic",       Arg.String (set_string_option_once "-ic" input_conn),
                                            "uri " ^ s_"Libvirt URI";
    "-if",       Arg.String (set_string_option_once "-if" input_format),
                                            "format " ^ s_"Input format (for -i disk)";
    "--in-place", Arg.Set in_place,         " " ^ s_"Unsupported option in RHEL 7";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-n",        Arg.String add_network,    "in:out " ^ s_"Map network 'in' to 'out'";
    "--network", Arg.String add_network,    "in:out " ^ ditto;
    "--no-copy", Arg.Clear do_copy,         " " ^ s_"Just write the metadata";
    "--no-trim", Arg.String set_no_trim,    "all|mp,mp,.." ^ " " ^ s_"Don't trim selected mounts";
    "-o",        Arg.String set_output_mode, o_options ^ " " ^ s_"Set output mode (default: libvirt)";
    "-oa",       Arg.String set_output_alloc,
                                            "sparse|preallocated " ^ s_"Set output allocation mode";
    "-oc",       Arg.String (set_string_option_once "-oc" output_conn),
                                            "uri " ^ s_"Libvirt URI";
    "-of",       Arg.String (set_string_option_once "-of" output_format),
                                            "raw|qcow2 " ^ s_"Set output format";
    "-on",       Arg.String (set_string_option_once "-on" output_name),
                                            "name " ^ s_"Rename guest when converting";
    "-os",       Arg.String (set_string_option_once "-os" output_storage),
                                            "storage " ^ s_"Set output storage location";
    "--password-file", Arg.String (set_string_option_once "--password-file" password_file),
                                            "file " ^ s_"Use password from file";
    "--print-source", Arg.Set print_source, " " ^ s_"Print source and stop";
    "--root",    Arg.String set_root_choice,"ask|... " ^ s_"How to choose root filesystem";
    "--vdsm-image-uuid", Arg.String add_vdsm_image_uuid, "uuid " ^ s_"Output image UUID(s)";
    "--vdsm-vol-uuid", Arg.String add_vdsm_vol_uuid, "uuid " ^ s_"Output vol UUID(s)";
    "--vdsm-vm-uuid", Arg.String (set_string_option_once "--vdsm-vm-uuid" vdsm_vm_uuid),
                                            "uuid " ^ s_"Output VM UUID";
    "--vdsm-ovf-output", Arg.String (set_string_option_once "--vdsm-ovf-output" vdsm_ovf_output),
                                            " " ^ s_"Output OVF file";
    "--vmtype",  Arg.String (set_string_option_once "--vmtype" vmtype),
                                            "server|desktop " ^ s_"Set vmtype (for RHEV)";
  ] in
  let argspec = set_standard_options argspec in
  let args = ref [] in
  let anon_fun s = push_front s args in
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
  let compressed = !compressed in
  let dcpath = !dcpath in
  let debug_overlays = !debug_overlays in
  let do_copy = !do_copy in
  let input_conn = !input_conn in
  let input_format = !input_format in
  let input_mode = !input_mode in
  let in_place = !in_place in
  let machine_readable = !machine_readable in
  let network_map = !network_map in
  let no_trim = !no_trim in
  let output_alloc =
    match !output_alloc with
    | `Not_set | `Sparse -> Sparse
    | `Preallocated -> Preallocated in
  let output_conn = !output_conn in
  let output_format = !output_format in
  let output_mode = !output_mode in
  let output_name = !output_name in
  let output_storage = !output_storage in
  let password_file = !password_file in
  let print_source = !print_source in
  let qemu_boot = !qemu_boot in
  let root_choice = !root_choice in
  let vdsm_image_uuids = List.rev !vdsm_image_uuids in
  let vdsm_vol_uuids = List.rev !vdsm_vol_uuids in
  let vdsm_vm_uuid = !vdsm_vm_uuid in
  let vdsm_ovf_output =
    match !vdsm_ovf_output with None -> "." | Some s -> s in
  let vmtype =
    match !vmtype with
    | Some "server" -> Some Server
    | Some "desktop" -> Some Desktop
    | None -> None
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
      let password = read_first_line_from_file filename in
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
      Input_disk.input_disk input_format disk

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
      Input_libvirt.input_libvirt dcpath password input_conn guest

    | `LibvirtXML ->
      (* -i libvirtxml: Expecting a filename (XML file). *)
      let filename =
        match args with
        | [filename] -> filename
        | _ ->
          error (f_"expecting a libvirt XML file name on the command line") in
      Input_libvirtxml.input_libvirtxml filename

    | `OVA ->
      (* -i ova: Expecting an ova filename (tar file). *)
      let filename =
        match args with
        | [filename] -> filename
        | _ ->
          error (f_"expecting an OVA file name on the command line") in
      Input_ova.input_ova filename in

  (* Prevent use of --in-place option in RHEL. *)
  if in_place then
    error (f_"--in-place cannot be used in RHEL 7");

  (* Parse the output mode. *)
  if output_mode <> `Not_set && in_place then
    error (f_"-o and --in-place cannot be used at the same time");
  let output =
    match output_mode with
    | `Glance ->
      if output_conn <> None then
        error (f_"-o glance: -oc option cannot be used in this output mode");
      if output_storage <> None then
        error (f_"-o glance: -os option cannot be used in this output mode");
      if qemu_boot then
        error (f_"-o glance: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o glance'");
      if not do_copy then
        error (f_"--no-copy and '-o glance' cannot be used at the same time");
      Output_glance.output_glance ()

    | `Not_set
    | `Libvirt ->
      let output_storage =
        match output_storage with None -> "default" | Some os -> os in
      if qemu_boot then
        error (f_"-o libvirt: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o libvirt'");
      if not do_copy then
        error (f_"--no-copy and '-o libvirt' cannot be used at the same time");
      Output_libvirt.output_libvirt output_conn output_storage

    | `Local ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o local: output directory was not specified, use '-os /dir'")
        | Some d when not (is_directory d) ->
           error (f_"-os %s: output directory does not exist or is not a directory") d
        | Some d -> d in
      if qemu_boot then
        error (f_"-o local: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o local'");
      Output_local.output_local os

    | `Null ->
      if output_conn <> None then
        error (f_"-o null: -oc option cannot be used in this output mode");
      if output_storage <> None then
        error (f_"-o null: -os option cannot be used in this output mode");
      if qemu_boot then
        error (f_"-o null: --qemu-boot option cannot be used in this output mode");
      if vmtype <> None then
        error (f_"--vmtype option cannot be used with '-o null'");
      Output_null.output_null ()

    | `QEmu ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o qemu: output directory was not specified, use '-os /dir'")
        | Some d when not (is_directory d) ->
           error (f_"-os %s: output directory does not exist or is not a directory") d
        | Some d -> d in
      if qemu_boot then
        error (f_"-o qemu: the --qemu-boot option cannot be used in RHEL");
      Output_qemu.output_qemu os qemu_boot

    | `RHEV ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o rhev: output storage was not specified, use '-os'");
        | Some d -> d in
      if qemu_boot then
        error (f_"-o rhev: --qemu-boot option cannot be used in this output mode");
      Output_rhev.output_rhev os vmtype output_alloc

    | `VDSM ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o vdsm: output storage was not specified, use '-os'");
        | Some d -> d in
      if qemu_boot then
        error (f_"-o vdsm: --qemu-boot option cannot be used in this output mode");
      let vdsm_vm_uuid =
        match vdsm_vm_uuid with
        | None ->
           error (f_"-o vdsm: --vdsm-image-uuid was not specified")
        | Some s -> s in
      if vdsm_image_uuids = [] || vdsm_vol_uuids = [] then
        error (f_"-o vdsm: either --vdsm-vol-uuid or --vdsm-vm-uuid was not specified");
      let vdsm_params = {
        Output_vdsm.image_uuids = vdsm_image_uuids;
        vol_uuids = vdsm_vol_uuids;
        vm_uuid = vdsm_vm_uuid;
        ovf_output = vdsm_ovf_output;
      } in
      Output_vdsm.output_vdsm os vdsm_params vmtype output_alloc in

  {
    compressed = compressed; debug_overlays = debug_overlays;
    do_copy = do_copy; in_place = in_place; network_map = network_map;
    no_trim = no_trim;
    output_alloc = output_alloc; output_format = output_format;
    output_name = output_name;
    print_source = print_source; root_choice = root_choice;
  },
  input, output
