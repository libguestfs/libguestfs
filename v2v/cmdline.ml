(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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
open Getopt.OptionName

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

  let input_conn = ref None in
  let input_format = ref None in
  let input_transport = ref None in
  let in_place = ref false in
  let output_conn = ref None in
  let output_format = ref None in
  let output_name = ref None in
  let output_storage = ref None in
  let password_file = ref None in
  let vddk_config = ref None in
  let vddk_cookie = ref None in
  let vddk_libdir = ref None in
  let vddk_nfchostport = ref None in
  let vddk_port = ref None in
  let vddk_snapshot = ref None in
  let vddk_thumbprint = ref None in
  let vddk_transports = ref None in
  let vddk_vimapiver = ref None in
  let vdsm_vm_uuid = ref None in
  let vdsm_ovf_output = ref None in (* default "." *)

  let vdsm_compat = ref "0.10" in
  let set_vdsm_compat s = vdsm_compat := s in

  let vdsm_ovf_flavour = ref OVF.RHVExportStorageDomain in
  let ovf_flavours_str = String.concat "|" OVF.ovf_flavours in
  let set_vdsm_ovf_flavour arg =
    vdsm_ovf_flavour := OVF.ovf_flavour_of_string arg in

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
    | "vmx" -> input_mode := `VMX
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

  let no_trim_warning _ =
    warning (f_"the --no-trim option has been removed and now does nothing")
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
    | "ovirt" | "rhv" | "rhev" -> output_mode := `RHV
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

  let vmtype_warning _ =
    warning (f_"the --vmtype option has been removed and now does nothing")
  in

  let i_options =
    String.concat "|" (Modules_list.input_modules ())
  and o_options =
    String.concat "|" (Modules_list.output_modules ()) in

  let argspec = [
    [ S 'b'; L"bridge" ],        Getopt.String ("in:out", add_bridge),     s_"Map bridge 'in' to 'out'";
    [ L"compressed" ], Getopt.Set compressed,     s_"Compress output file (-of qcow2 only)";
    [ L"debug-overlay"; L"debug-overlays" ], Getopt.Set debug_overlays, s_"Save overlay files";
    [ S 'i' ],        Getopt.String (i_options, set_input_mode), s_"Set input mode (default: libvirt)";
    [ M"ic" ],       Getopt.String ("uri", set_string_option_once "-ic" input_conn),
                                            s_"Libvirt URI";
    [ M"if" ],       Getopt.String ("format", set_string_option_once "-if" input_format),
                                            s_"Input format (for -i disk)";
    [ M"it" ],       Getopt.String ("transport", set_string_option_once "-it" input_transport),
                                    s_"Input transport";
    [ L"in-place" ], Getopt.Set in_place,         "";
    [ L"machine-readable" ], Getopt.Set machine_readable, s_"Make output machine readable";
    [ S 'n'; L"network" ],        Getopt.String ("in:out", add_network),    s_"Map network 'in' to 'out'";
    [ L"no-copy" ], Getopt.Clear do_copy,         s_"Just write the metadata";
    [ L"no-trim" ], Getopt.String ("-", no_trim_warning),
                                            s_"Ignored for backwards compatibility";
    [ S 'o' ],        Getopt.String (o_options, set_output_mode), s_"Set output mode (default: libvirt)";
    [ M"oa" ],       Getopt.String ("sparse|preallocated", set_output_alloc),
                                            s_"Set output allocation mode";
    [ M"oc" ],       Getopt.String ("uri", set_string_option_once "-oc" output_conn),
                                    s_"Output hypervisor connection";
    [ M"of" ],       Getopt.String ("raw|qcow2", set_string_option_once "-of" output_format),
                                            s_"Set output format";
    [ M"on" ],       Getopt.String ("name", set_string_option_once "-on" output_name),
                                            s_"Rename guest when converting";
    [ M"os" ],       Getopt.String ("storage", set_string_option_once "-os" output_storage),
                                            s_"Set output storage location";
    [ L"password-file" ], Getopt.String ("file", set_string_option_once "--password-file" password_file),
                                            s_"Use password from file";
    [ L"print-source" ], Getopt.Set print_source, s_"Print source and stop";
    [ L"root" ],    Getopt.String ("ask|... ", set_root_choice), s_"How to choose root filesystem";
    [ L"vddk-config" ], Getopt.String ("filename", set_string_option_once "--vddk-config" vddk_config),
                                            s_"Set VDDK config file";
    [ L"vddk-cookie" ], Getopt.String ("cookie", set_string_option_once "--vddk-cookie" vddk_cookie),
                                            s_"Set VDDK cookie";
    [ L"vddk-libdir" ], Getopt.String ("libdir", set_string_option_once "--vddk-libdir" vddk_libdir),
                                    s_"Set VDDK library parent directory";
    [ L"vddk-nfchostport" ], Getopt.String ("nfchostport", set_string_option_once "--vddk-nfchostport" vddk_nfchostport),
                                            s_"Set VDDK nfchostport";
    [ L"vddk-port" ], Getopt.String ("port", set_string_option_once "--vddk-port" vddk_port),
                                            s_"Set VDDK port";
    [ L"vddk-snapshot" ], Getopt.String ("snapshot-moref", set_string_option_once "--vddk-snapshot" vddk_snapshot),
                                            s_"Set VDDK snapshot";
    [ L"vddk-thumbprint" ], Getopt.String ("thumbprint", set_string_option_once "--vddk-thumbprint" vddk_thumbprint),
                                            s_"Set VDDK thumbprint";
    [ L"vddk-transports" ], Getopt.String ("transports", set_string_option_once "--vddk-transports" vddk_transports),
                                            s_"Set VDDK transports";
    [ L"vddk-vimapiver" ], Getopt.String ("apiver", set_string_option_once "--vddk-vimapiver" vddk_vimapiver),
                                            s_"Set VDDK vimapiver";
    [ L"vdsm-compat" ], Getopt.Symbol ("0.10|1.1", ["0.10"; "1.1"], set_vdsm_compat), s_"Write qcow2 with compat=0.10|1.1";
    [ L"vdsm-image-uuid" ], Getopt.String ("uuid", add_vdsm_image_uuid), s_"Output image UUID(s)";
    [ L"vdsm-vol-uuid" ], Getopt.String ("uuid", add_vdsm_vol_uuid), s_"Output vol UUID(s)";
    [ L"vdsm-vm-uuid" ], Getopt.String ("uuid", set_string_option_once "--vdsm-vm-uuid" vdsm_vm_uuid),
                                            s_"Output VM UUID";
    [ L"vdsm-ovf-output" ], Getopt.String ("-", set_string_option_once "--vdsm-ovf-output" vdsm_ovf_output),
                                            s_"Output OVF file";
    [ L"vdsm-ovf-flavour" ], Getopt.Symbol (ovf_flavours_str, OVF.ovf_flavours, set_vdsm_ovf_flavour),
                                    s_"Set the type of generated OVF (default rhvexp)";
    [ L"vmtype" ],  Getopt.String ("-", vmtype_warning),
                                            s_"Ignored for backwards compatibility";
  ] in
  let args = ref [] in
  let anon_fun s = push_front s args in
  let usage_msg =
    sprintf (f_"\
%s: convert a guest to use KVM

 virt-v2v -ic vpx://vcenter.example.com/Datacenter/esxi -os imported esx_guest

 virt-v2v -ic vpx://vcenter.example.com/Datacenter/esxi esx_guest \
   -o rhv -os rhv.nfs:/export_domain --network ovirtmgmt

 virt-v2v -i libvirtxml guest-domain.xml -o local -os /var/tmp

 virt-v2v -i disk disk.img -o local -os /var/tmp

 virt-v2v -i disk disk.img -o glance

There is a companion front-end called \"virt-p2v\" which comes as an
ISO or CD image that can be booted on physical machines.

A short summary of the options is given below.  For detailed help please
read the man page virt-v2v(1).
")
      prog in
  let opthandle = create_standard_options argspec ~anon_fun ~key_opts:true usage_msg in
  Getopt.parse opthandle;

  (* Dereference the arguments. *)
  let args = List.rev !args in
  let compressed = !compressed in
  let debug_overlays = !debug_overlays in
  let do_copy = !do_copy in
  let input_conn = !input_conn in
  let input_format = !input_format in
  let input_mode = !input_mode in
  let input_transport =
    match !input_transport with
    | None -> None
    | Some "ssh" -> Some `SSH
    | Some "vddk" -> Some `VDDK
    | Some transport ->
       error (f_"unknown input transport ‘-it %s’") transport in
  let in_place = !in_place in
  let machine_readable = !machine_readable in
  let network_map = !network_map in
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
  let vddk_options =
      { vddk_config = !vddk_config;
        vddk_cookie = !vddk_cookie;
        vddk_libdir = !vddk_libdir;
        vddk_nfchostport = !vddk_nfchostport;
        vddk_port = !vddk_port;
        vddk_snapshot = !vddk_snapshot;
        vddk_thumbprint = !vddk_thumbprint;
        vddk_transports = !vddk_transports;
        vddk_vimapiver = !vddk_vimapiver } in
  let vdsm_compat = !vdsm_compat in
  let vdsm_image_uuids = List.rev !vdsm_image_uuids in
  let vdsm_vol_uuids = List.rev !vdsm_vol_uuids in
  let vdsm_vm_uuid = !vdsm_vm_uuid in
  let vdsm_ovf_output =
    match !vdsm_ovf_output with None -> "." | Some s -> s in
  let vdsm_ovf_flavour = !vdsm_ovf_flavour in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if args = [] && machine_readable then (
    printf "virt-v2v\n";
    printf "libguestfs-rewrite\n";
    printf "vcenter-https\n";
    printf "xen-ssh\n";
    printf "vddk\n";
    printf "colours-option\n";
    printf "vdsm-compat-option\n";
    List.iter (printf "input:%s\n") (Modules_list.input_modules ());
    List.iter (printf "output:%s\n") (Modules_list.output_modules ());
    List.iter (printf "convert:%s\n") (Modules_list.convert_modules ());
    List.iter (printf "ovf:%s\n") OVF.ovf_flavours;
    exit 0
  );

  (* Parse out the password from the password file. *)
  let password =
    match password_file with
    | None -> None
    | Some filename ->
      let password = read_first_line_from_file filename in
      Some password in

  (* Input transport affects whether some parameters should or
   * should not be used.
   *)
  (match input_transport with
   | None
   | Some `SSH ->
      if !vddk_config <> None ||
         !vddk_cookie <> None ||
         !vddk_libdir <> None ||
         !vddk_nfchostport <> None ||
         !vddk_port <> None ||
         !vddk_snapshot <> None ||
         !vddk_thumbprint <> None ||
         !vddk_transports <> None ||
         !vddk_vimapiver <> None then
        error (f_"‘--vddk-*’ options should only be used when conversion via the nbdkit VDDK plugin has been enabled, ie. using ‘-it vddk’.")
   | Some `VDDK ->
      if !vddk_thumbprint = None then
        error (f_"‘--vddk-thumbprint’ is required when using ‘-it vddk’.")
  );

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
      let input_transport =
        match input_transport with
        | None -> None
        | Some `VDDK -> Some `VDDK
        | Some `SSH ->
           error (f_"only ‘-it vddk’ can be used here") in
      Input_libvirt.input_libvirt vddk_options password
                                  input_conn input_transport guest

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
      Input_ova.input_ova filename

    | `VMX ->
      (* -i vmx: Expecting a vmx filename or SSH remote path. *)
      let arg =
        match args with
        | [arg] -> arg
        | _ ->
          error (f_"expecting a single VMX file name or SSH remote path on the command line") in
      let input_transport =
        match input_transport with
        | None -> None
        | Some `SSH -> Some `SSH
        | Some `VDDK ->
           error (f_"only ‘-it ssh’ can be used here") in
      Input_vmx.input_vmx input_transport arg in

  (* Prevent use of --in-place option in RHEL. *)
  if in_place then
    error (f_"--in-place cannot be used in RHEL 7");

  (* Common error message. *)
  let error_option_cannot_be_used_in_output_mode mode opt =
    error (f_"-o %s: %s option cannot be used in this output mode") mode opt
  in

  (* Parse the output mode. *)
  if output_mode <> `Not_set && in_place then
    error (f_"-o and --in-place cannot be used at the same time");
  let output, output_format, output_alloc =
    match output_mode with
    | `Glance ->
      if output_conn <> None then
        error_option_cannot_be_used_in_output_mode "glance" "-oc";
      if output_storage <> None then
        error_option_cannot_be_used_in_output_mode "glance" "-os";
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "glance" "--qemu-boot";
      if not do_copy then
        error_option_cannot_be_used_in_output_mode "glance" "--no-copy";
      Output_glance.output_glance (),
      output_format, output_alloc

    | `Not_set
    | `Libvirt ->
      let output_storage =
        match output_storage with None -> "default" | Some os -> os in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "libvirt" "--qemu-boot";
      if not do_copy then
        error_option_cannot_be_used_in_output_mode "libvirt" "--no-copy";
      Output_libvirt.output_libvirt output_conn output_storage,
      output_format, output_alloc

    | `Local ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o local: output directory was not specified, use '-os /dir'")
        | Some d when not (is_directory d) ->
           error (f_"-os %s: output directory does not exist or is not a directory") d
        | Some d -> d in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "local" "--qemu-boot";
      Output_local.output_local os,
      output_format, output_alloc

    | `Null ->
      if output_alloc <> Sparse then
        error_option_cannot_be_used_in_output_mode "null" "-oa";
      if output_conn <> None then
        error_option_cannot_be_used_in_output_mode "null" "-oc";
      if output_format <> None then
        error_option_cannot_be_used_in_output_mode "null" "-of";
      if output_storage <> None then
        error_option_cannot_be_used_in_output_mode "null" "-os";
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "null" "--qemu-boot";
      Output_null.output_null (),
      (* Force output format to raw sparse in -o null mode. *)
      Some "raw", Sparse

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
      Output_qemu.output_qemu os qemu_boot,
      output_format, output_alloc

    | `RHV ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o rhv: output storage was not specified, use '-os'");
        | Some d -> d in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "rhv" "--qemu-boot";
      Output_rhv.output_rhv os output_alloc,
      output_format, output_alloc

    | `VDSM ->
      let os =
        match output_storage with
        | None ->
           error (f_"-o vdsm: output storage was not specified, use '-os'");
        | Some d -> d in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "vdsm" "--qemu-boot";
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
        compat = vdsm_compat;
        ovf_flavour = vdsm_ovf_flavour;
      } in
      Output_vdsm.output_vdsm os vdsm_params output_alloc,
      output_format, output_alloc in

  {
    compressed = compressed; debug_overlays = debug_overlays;
    do_copy = do_copy; in_place = in_place; network_map = network_map;
    output_alloc = output_alloc; output_format = output_format;
    output_name = output_name;
    print_source = print_source; root_choice = root_choice;
  },
  input, output
