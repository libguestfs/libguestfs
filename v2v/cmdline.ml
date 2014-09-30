(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext
open Getopt.OptionName

open Types
open Utils

type cmdline = {
  compressed : bool;
  debug_overlays : bool;
  do_copy : bool;
  in_place : bool;
  network_map : Networks.t;
  output_alloc : output_allocation;
  output_format : string option;
  output_name : string option;
  print_estimate : bool;
  print_source : bool;
  root_choice : root_choice;
  ks : Tools_utils.key_store;
}

(* Matches --mac command line parameters. *)
let mac_re = PCRE.compile ~anchored:true "([[:xdigit:]]{2}:[[:xdigit:]]{2}:[[:xdigit:]]{2}:[[:xdigit:]]{2}:[[:xdigit:]]{2}:[[:xdigit:]]{2}):(network|bridge):(.*)"

let parse_cmdline () =
  let compressed = ref false in
  let debug_overlays = ref false in
  let do_copy = ref true in
  let print_estimate = ref false in
  let print_source = ref false in
  let qemu_boot = ref false in

  let input_conn = ref None in
  let input_format = ref None in
  let input_password = ref None in
  let input_transport = ref None in
  let in_place = ref false in
  let output_conn = ref None in
  let output_format = ref None in
  let output_name = ref None in
  let output_password = ref None in
  let output_storage = ref None in

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

  let input_options = ref [] in
  let set_input_option_compat k v =
    input_options := (k, v) :: !input_options
  in
  let set_input_option option =
    let k, v = String.split "=" option in
    set_input_option_compat k v
  in

  let network_map = Networks.create () in
  let add_network str =
    match String.split ":" str with
    | "", "" ->
       error (f_"invalid -n/--network parameter")
    | out, "" | "", out ->
       Networks.add_default_network network_map out
    | in_, out ->
       Networks.add_network network_map in_ out
  in
  let add_bridge str =
    match String.split ":" str with
    | "", "" ->
       error (f_"invalid -b/--bridge parameter")
    | out, "" | "", out ->
       Networks.add_default_bridge network_map out
    | in_, out ->
       Networks.add_bridge network_map in_ out
  in
  let add_mac str =
    if not (PCRE.matches mac_re str) then
      error (f_"cannot parse --mac \"%s\" parameter") str;
    let mac = PCRE.sub 1 and out = PCRE.sub 3 in
    let vnet_type =
      match PCRE.sub 2 with
      | "network" -> Network | "bridge" -> Bridge
      | _ -> assert false in
    Networks.add_mac network_map mac vnet_type out
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
    | "openstack" | "osp" | "rhosp" -> output_mode := `Openstack
    | "ovirt" | "rhv" | "rhev" -> output_mode := `RHV
    | "ovirt-upload" | "ovirt_upload" | "rhv-upload" | "rhv_upload" ->
       output_mode := `RHV_Upload
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

  let output_options = ref [] in
  let set_output_option_compat k v =
    output_options := (k, v) :: !output_options
  in
  let set_output_option option =
    let k, v = String.split "=" option in
    set_output_option_compat k v
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

  let vmtype_warning _ =
    warning (f_"the --vmtype option has been removed and now does nothing")
  in

  let i_options =
    String.concat "|" (Modules_list.input_modules ())
  and o_options =
    String.concat "|" (Modules_list.output_modules ())
  and ovf_flavours_str = String.concat "|" Create_ovf.ovf_flavours in

  let argspec = [
    [ S 'b'; L"bridge" ], Getopt.String ("in:out", add_bridge),
                                    s_"Map bridge ‘in’ to ‘out’";
    [ L"compressed" ], Getopt.Set compressed,
                                    s_"Compress output file (-of qcow2 only)";
    [ L"debug-overlay"; L"debug-overlays" ], Getopt.Set debug_overlays,
                                    s_"Save overlay files";
    [ S 'i' ],       Getopt.String (i_options, set_input_mode),
                                    s_"Set input mode (default: libvirt)";
    [ M"ic" ],       Getopt.String ("uri", set_string_option_once "-ic" input_conn),
                                    s_"Libvirt URI";
    [ M"if" ],       Getopt.String ("format", set_string_option_once "-if" input_format),
                                    s_"Input format (for -i disk)";
    [ M"io" ],       Getopt.String ("option[=value]", set_input_option),
                                    s_"Set option for input mode";
    [ M"ip" ],       Getopt.String ("filename", set_string_option_once "-ip" input_password),
                                    s_"Use password from file to connect to input hypervisor";
    [ M"it" ],       Getopt.String ("transport", set_string_option_once "-it" input_transport),
                                    s_"Input transport";
    [ L"in-place" ], Getopt.Set in_place,
                                    s_"Only tune the guest in the input VM";
    [ L"mac" ],      Getopt.String ("mac:network|bridge:out", add_mac),
                                    s_"Map NIC to network or bridge";
    [ S 'n'; L"network" ], Getopt.String ("in:out", add_network),
                                    s_"Map network ‘in’ to ‘out’";
    [ L"no-copy" ],  Getopt.Clear do_copy,
                                    s_"Just write the metadata";
    [ L"no-trim" ],  Getopt.String ("-", no_trim_warning),
                                    s_"Ignored for backwards compatibility";
    [ S 'o' ],       Getopt.String (o_options, set_output_mode),
                                    s_"Set output mode (default: libvirt)";
    [ M"oa" ],       Getopt.String ("sparse|preallocated", set_output_alloc),
                                    s_"Set output allocation mode";
    [ M"oc" ],       Getopt.String ("uri", set_string_option_once "-oc" output_conn),
                                    s_"Output hypervisor connection";
    [ M"of" ],       Getopt.String ("raw|qcow2", set_string_option_once "-of" output_format),
                                    s_"Set output format";
    [ M"on" ],       Getopt.String ("name", set_string_option_once "-on" output_name),
                                    s_"Rename guest when converting";
    [ M"oo" ],       Getopt.String ("option[=value]", set_output_option),
                                    s_"Set option for output mode";
    [ M"op" ],       Getopt.String ("filename", set_string_option_once "-op" output_password),
                                    s_"Use password from file to connect to output hypervisor";
    [ M"os" ],       Getopt.String ("storage", set_string_option_once "-os" output_storage),
                                    s_"Set output storage location";
    [ L"password-file" ], Getopt.String ("filename", set_string_option_once "--password-file" input_password),
                                    s_"Same as ‘-ip filename’";
    [ L"print-estimate" ], Getopt.Set print_estimate,
                                    s_"Estimate size of source and stop";
    [ L"print-source" ], Getopt.Set print_source,
                                    s_"Print source and stop";
    [ L"root" ],     Getopt.String ("ask|... ", set_root_choice),
                                    s_"How to choose root filesystem";
    [ L"vddk-config" ], Getopt.String ("filename", set_input_option_compat "vddk-config"),
                                    s_"Same as ‘-io vddk-config=filename’";
    [ L"vddk-cookie" ], Getopt.String ("cookie", set_input_option_compat "vddk-cookie"),
                                    s_"Same as ‘-io vddk-cookie=filename’";
    [ L"vddk-libdir" ], Getopt.String ("libdir", set_input_option_compat "vddk-libdir"),
                                    s_"Same as ‘-io vddk-libdir=libdir’";
    [ L"vddk-nfchostport" ], Getopt.String ("nfchostport", set_input_option_compat "vddk-nfchostport"),
                                    s_"Same as ‘-io vddk-nfchostport=nfchostport’";
    [ L"vddk-port" ], Getopt.String ("port", set_input_option_compat "vddk-port"),
                                    s_"Same as ‘-io vddk-port=port’";
    [ L"vddk-snapshot" ], Getopt.String ("snapshot-moref", set_input_option_compat "vddk-snapshot"),
                                    s_"Same as ‘-io vddk-snapshot=snapshot-moref’";
    [ L"vddk-thumbprint" ], Getopt.String ("thumbprint", set_input_option_compat "vddk-thumbprint"),
                                    s_"Same as ‘-io vddk-thumbprint=thumbprint’";
    [ L"vddk-transports" ], Getopt.String ("transports", set_input_option_compat "vddk-transports"),
                                    s_"Same as ‘-io vddk-transports=transports’";
    [ L"vdsm-compat" ], Getopt.String ("0.10|1.1", set_output_option_compat "vdsm-compat"),
                                    s_"Same as ‘-oo vdsm-compat=0.10|1.1’";
    [ L"vdsm-image-uuid" ], Getopt.String ("uuid", set_output_option_compat "vdsm-image-uuid"),
                                    s_"Same as ‘-oo vdsm-image-uuid=uuid’";
    [ L"vdsm-vol-uuid" ], Getopt.String ("uuid", set_output_option_compat "vdsm-vol-uuid"),
                                    s_"Same as ‘-oo vdsm-vol-uuid=uuid’";
    [ L"vdsm-vm-uuid" ], Getopt.String ("uuid", set_output_option_compat "vdsm-vm-uuid"),
                                    s_"Same as ‘-oo vdsm-vm-uuid=uuid’";
    [ L"vdsm-ovf-output" ], Getopt.String ("dir", set_output_option_compat "vdsm-ovf-output"),
                                    s_"Same as ‘-oo vdsm-ovf-output=dir’";
    [ L"vdsm-ovf-flavour" ], Getopt.String (ovf_flavours_str, set_output_option_compat "vdsm-ovf-flavour"),
                                    s_"Same as ‘-oo vdsm-ovf-flavour=flavour’";
    [ L"vmtype" ],   Getopt.String ("-", vmtype_warning),
                                    s_"Ignored for backwards compatibility";
  ] in
  let args = ref [] in
  let anon_fun s = List.push_front s args in
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
  let opthandle = create_standard_options argspec ~anon_fun ~key_opts:true ~machine_readable:true usage_msg in
  Getopt.parse opthandle.getopt;

  (* Dereference the arguments. *)
  let args = List.rev !args in
  let compressed = !compressed in
  let debug_overlays = !debug_overlays in
  let do_copy = !do_copy in
  let input_conn = !input_conn in
  let input_format = !input_format in
  let input_mode = !input_mode in
  let input_options = List.rev !input_options in
  let input_password = !input_password in
  let input_transport =
    match !input_transport with
    | None -> None
    | Some "ssh" -> Some `SSH
    | Some "vddk" -> Some `VDDK
    | Some transport ->
       error (f_"unknown input transport ‘-it %s’") transport in
  let in_place = !in_place in
  let output_alloc =
    match !output_alloc with
    | `Not_set | `Sparse -> Sparse
    | `Preallocated -> Preallocated in
  let output_conn = !output_conn in
  let output_format = !output_format in
  let output_mode = !output_mode in
  let output_name = !output_name in
  let output_options = List.rev !output_options in
  let output_password = !output_password in
  let output_storage = !output_storage in
  let print_estimate = !print_estimate in
  let print_source = !print_source in
  let qemu_boot = !qemu_boot in
  let root_choice = !root_choice in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  (match args, machine_readable () with
  | [], Some { pr } ->
    pr "virt-v2v\n";
    pr "libguestfs-rewrite\n";
    pr "vcenter-https\n";
    pr "xen-ssh\n";
    pr "vddk\n";
    pr "colours-option\n";
    pr "vdsm-compat-option\n";
    pr "in-place\n";
    pr "io/oo\n";
    pr "mac-option\n";
    List.iter (pr "input:%s\n") (Modules_list.input_modules ());
    List.iter (pr "output:%s\n") (Modules_list.output_modules ());
    List.iter (pr "convert:%s\n") (Modules_list.convert_modules ());
    List.iter (pr "ovf:%s\n") Create_ovf.ovf_flavours;
    exit 0
  | _, _ -> ()
  );

  (* Some options cannot be used with --in-place. *)
  if in_place then (
    if print_estimate then
      error (f_"--in-place and --print-estimate cannot be used together")
  );

  (* Input transport affects whether some input options should or
   * should not be used.
   *)
  let input_transport =
    let is_query = input_options = ["?", ""] in
    let no_options () =
      if is_query then (
        printf (f_"No -io (input options) are supported with this input transport.\n");
        exit 0
      )
      else if input_options <> [] then
        error (f_"no -io (input options) are allowed here");
    in
    match input_transport with
    | None -> no_options (); None
    | Some `SSH -> no_options (); Some `SSH
    | Some `VDDK ->
       if is_query then (
         Input_libvirt_vddk.print_input_options ();
         exit 0
       )
       else (
         let vddk_options =
           Input_libvirt_vddk.parse_input_options input_options in
         Some (`VDDK vddk_options)
       ) in

  (* Output mode affects whether some output options should or
   * should not be used.
   *)
  let output_mode =
    let is_query = output_options = ["?", ""] in
    let no_options () =
      if is_query then (
        printf (f_"No -oo (output options) are supported in this output mode.\n");
        exit 0
      )
      else if output_options <> [] then
        error (f_"no -oo (output options) are allowed here");
    in
    match output_mode with
    | `Not_set -> no_options (); `Not_set
    | `Glance -> no_options (); `Glance
    | `Libvirt -> no_options (); `Libvirt
    | `Local -> no_options (); `Local
    | `Null -> no_options (); `Null
    | `RHV -> no_options (); `RHV
    | `QEmu -> no_options (); `QEmu

    | `Openstack ->
       if is_query then (
         Output_openstack.print_output_options ();
         exit 0
       )
       else (
         let os_options =
           Output_openstack.parse_output_options output_options in
         `Openstack os_options
       )

    | `RHV_Upload ->
       if is_query then (
         Output_rhv_upload.print_output_options ();
         exit 0
       )
       else (
         let rhv_options =
           Output_rhv_upload.parse_output_options output_options in
         `RHV_Upload rhv_options
       )

    | `VDSM ->
       if is_query then (
         Output_vdsm.print_output_options ();
         exit 0
       )
       else (
         let vdsm_options =
           Output_vdsm.parse_output_options output_options in
         `VDSM vdsm_options
       ) in

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
        | (Some (`VDDK _) as vddk) -> vddk
        | Some `SSH ->
           error (f_"only ‘-it vddk’ can be used here") in
      Input_libvirt.input_libvirt input_conn input_password input_transport
                                  guest

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
        | Some (`VDDK _) ->
           error (f_"only ‘-it ssh’ can be used here") in
      Input_vmx.input_vmx input_transport arg in

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
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "glance" "-op";
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
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "libvirt" "-op";
      let output_storage = Option.default "default" output_storage in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "libvirt" "--qemu-boot";
      if not do_copy then
        error_option_cannot_be_used_in_output_mode "libvirt" "--no-copy";
      Output_libvirt.output_libvirt output_conn output_storage,
      output_format, output_alloc

    | `Local ->
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "local" "-op";
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
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "null" "-op";
      if output_storage <> None then
        error_option_cannot_be_used_in_output_mode "null" "-os";
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "null" "--qemu-boot";
      Output_null.output_null (),
      (* Force output format to raw sparse in -o null mode. *)
      Some "raw", Sparse

    | `QEmu ->
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "qemu" "-op";
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

    | `Openstack os_options ->
      if output_alloc <> Sparse then
        error_option_cannot_be_used_in_output_mode "openstack" "-oa";
      if output_format <> None then
        error_option_cannot_be_used_in_output_mode "openstack" "-of";
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "openstack" "--qemu-boot";
      Output_openstack.output_openstack output_conn output_password
                                        output_storage os_options,
      (* Force output format to raw sparse in -o openstack mode. *)
      Some "raw", Sparse

    | `RHV ->
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "rhv" "-op";
      let os =
        match output_storage with
        | None ->
           error (f_"-o rhv: output storage was not specified, use ‘-os’");
        | Some d -> d in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "rhv" "--qemu-boot";
      Output_rhv.output_rhv os output_alloc,
      output_format, output_alloc

    | `RHV_Upload rhv_options ->
      let output_conn =
        match output_conn with
        | None ->
           error (f_"-o rhv-upload: use ‘-oc’ to point to the oVirt or RHV server REST API URL, which is usually https://servername/ovirt-engine/api")
        | Some oc -> oc in
      (* In theory we could make the password optional in future. *)
      let output_password =
        match output_password with
        | None ->
           error (f_"-o rhv-upload: output password file was not specified, use ‘-op’ to point to a file which contains the password used to connect to the oVirt or RHV server")
        | Some op -> op in
      let os =
        match output_storage with
        | None ->
           error (f_"-o rhv-upload: output storage was not specified, use ‘-os’");
        | Some os -> os in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "rhv-upload" "--qemu-boot";
      Output_rhv_upload.output_rhv_upload output_alloc output_conn
                                          output_password os
                                          rhv_options,
      output_format, output_alloc

    | `VDSM vdsm_options ->
      if output_password <> None then
        error_option_cannot_be_used_in_output_mode "vdsm" "-op";
      let os =
        match output_storage with
        | None ->
           error (f_"-o vdsm: output storage was not specified, use ‘-os’");
        | Some d -> d in
      if qemu_boot then
        error_option_cannot_be_used_in_output_mode "vdsm" "--qemu-boot";
      Output_vdsm.output_vdsm os vdsm_options output_alloc,
      output_format, output_alloc in

  {
    compressed; debug_overlays; do_copy; in_place; network_map;
    output_alloc; output_format; output_name;
    print_estimate; print_source; root_choice;
    ks = opthandle.ks;
  },
  input, output
