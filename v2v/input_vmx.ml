(* virt-v2v
 * Copyright (C) 2017 Red Hat Inc.
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

open Printf
open Scanf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils
open Name_from_disk

external identity : 'a -> 'a = "%identity"

let rec find_disks vmx vmx_filename =
  find_scsi_disks vmx vmx_filename @ find_ide_disks vmx vmx_filename

(* Find all SCSI hard disks.
 *
 * In the VMX file:
 *   scsi0.virtualDev = "pvscsi"  # or may be "lsilogic" etc.
 *   scsi0:0.deviceType = "scsi-hardDisk"
 *   scsi0:0.fileName = "guest.vmdk"
 *)
and find_scsi_disks vmx vmx_filename =
  let get_scsi_controller_target ns =
    sscanf ns "scsi%d:%d" (fun c t -> c, t)
  in
  let is_scsi_controller_target ns =
    try ignore (get_scsi_controller_target ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in
  let scsi_device_types = [ "scsi-harddisk" ] in
  let scsi_controller = Source_SCSI in

  find_hdds vmx vmx_filename
            get_scsi_controller_target is_scsi_controller_target
            scsi_device_types scsi_controller

(* Find all IDE hard disks.
 *
 * In the VMX file:
 *   ide0:0.deviceType = "ata-hardDisk"
 *   ide0:0.fileName = "guest.vmdk"
 *)
and find_ide_disks vmx vmx_filename =
  let get_ide_controller_target ns =
    sscanf ns "ide%d:%d" (fun c t -> c, t)
  in
  let is_ide_controller_target ns =
    try ignore (get_ide_controller_target ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in
  let ide_device_types = [ "ata-harddisk" ] in
  let ide_controller = Source_IDE in

  find_hdds vmx vmx_filename
            get_ide_controller_target is_ide_controller_target
            ide_device_types ide_controller

and find_hdds vmx vmx_filename
              get_controller_target is_controller_target
              device_types controller =
  (* Find namespaces matching '(ide|scsi)X:Y' with suitable deviceType. *)
  let hdds =
    Parse_vmx.select_namespaces (
      function
      | [ns] ->
         (* Check the namespace is '(ide|scsi)X:Y' *)
         if not (is_controller_target ns) then false
         else (
           (* Check the deviceType is one we are looking for. *)
           match Parse_vmx.get_string vmx [ns; "deviceType"] with
           | Some str ->
              let str = String.lowercase_ascii str in
              List.mem str device_types
           | None -> false
         )
      | _ -> false
    ) vmx in

  (* Map the subset to a list of disks. *)
  let hdds =
    Parse_vmx.map (
      fun path v ->
        match path, v with
        | [ns; "filename"], Some filename ->
           let c, t = get_controller_target ns in
           let s = { s_disk_id = (-1);
                     s_qemu_uri = qemu_uri_of_filename vmx_filename filename;
                     s_format = Some "vmdk";
                     s_controller = Some controller } in
           Some (c, t, s)
        | _ -> None
    ) hdds in
  let hdds = filter_map identity hdds in

  (* We don't have a way to return the controllers and targets, so
   * just make sure the disks are sorted into order, since Parse_vmx
   * won't return them in any particular order.
   *)
  let hdds = List.sort compare hdds in
  let hdds = List.map (fun (_, _, source) -> source) hdds in

  (* Set the s_disk_id field to an incrementing number. *)
  let hdds = mapi (fun i source -> { source with s_disk_id = i }) hdds in

  hdds

(* The filename can be an absolute path, but is more often a
 * path relative to the location of the vmx file.
 *
 * Note that we always end up with an absolute path, which is
 * also useful because it means we won't have any paths that
 * could be misinterpreted by qemu.
 *)
and qemu_uri_of_filename vmx_filename filename =
  if not (Filename.is_relative filename) then
    filename
  else (
    let dir = Filename.dirname (absolute_path vmx_filename) in
    dir // filename
  )

(* Find all removable disks.
 *
 * In the VMX file:
 *   ide1:0.deviceType = "cdrom-image"
 *   ide1:0.fileName = "boot.iso"
 *
 * XXX This only supports IDE CD-ROMs, but we could support SCSI
 * CD-ROMs and floppies in future.
 *)
and find_removables vmx =
  let get_ide_controller_target ns =
    sscanf ns "ide%d:%d" (fun c t -> c, t)
  in
  let is_ide_controller_target ns =
    try ignore (get_ide_controller_target ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in
  let device_types = [ "atapi-cdrom";
                       "cdrom-image"; "cdrom-raw" ] in

  (* Find namespaces matching 'ideX:Y' with suitable deviceType. *)
  let devs =
    Parse_vmx.select_namespaces (
      function
      | [ns] ->
         (* Check the namespace is 'ideX:Y' *)
         if not (is_ide_controller_target ns) then false
         else (
           (* Check the deviceType is one we are looking for. *)
           match Parse_vmx.get_string vmx [ns; "deviceType"] with
           | Some str ->
              let str = String.lowercase_ascii str in
              List.mem str device_types
           | None -> false
         )
      | _ -> false
    ) vmx in

  (* Map the subset to a list of CD-ROMs. *)
  let devs =
    Parse_vmx.map (
      fun path v ->
        match path, v with
        | [ns], None ->
           let c, t = get_ide_controller_target ns in
           let s = { s_removable_type = CDROM;
                     s_removable_controller = Some Source_IDE;
                     s_removable_slot = Some (ide_slot c t) } in
           Some s
        | _ -> None
    ) devs in
  let devs = filter_map identity devs in

  (* Sort by slot. *)
  let devs =
    List.sort
      (fun { s_removable_slot = s1 } { s_removable_slot = s2 } ->
        compare s1 s2)
      devs in

  devs

and ide_slot c t =
  (* Assuming the old master/slave arrangement. *)
  c * 2 + t

(* Find all ethernet cards.
 *
 * In the VMX file:
 *   ethernet0.virtualDev = "vmxnet3"
 *   ethernet0.networkName = "VM Network"
 *   ethernet0.generatedAddress = "00:01:02:03:04:05"
 *   ethernet0.connectionType = "bridged" # also: "custom", "nat" or not present
 *)
and find_nics vmx =
  let get_ethernet_port ns =
    sscanf ns "ethernet%d" (fun p -> p)
  in
  let is_ethernet_port ns =
    try ignore (get_ethernet_port ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in

  (* Find namespaces matching 'ethernetX'. *)
  let nics =
    Parse_vmx.select_namespaces (
      function
      | [ns] -> is_ethernet_port ns
      | _ -> false
    ) vmx in

  (* Map the subset to a list of NICs. *)
  let nics =
    Parse_vmx.map (
      fun path v ->
        match path, v with
        | [ns], None ->
           let port = get_ethernet_port ns in
           let mac = Parse_vmx.get_string vmx [ns; "generatedAddress"] in
           let model = Parse_vmx.get_string vmx [ns; "virtualDev"] in
           let model =
             match model with
             | Some m when String.lowercase_ascii m = "e1000" ->
                Some Source_e1000
             | Some model ->
                Some (Source_other_nic (String.lowercase_ascii model))
             | None -> None in
           let vnet = Parse_vmx.get_string vmx [ns; "networkName"] in
           let vnet =
             match vnet with
             | Some vnet -> vnet
             | None -> ns (* "ethernetX" *) in
           let vnet_type =
             match Parse_vmx.get_string vmx [ns; "connectionType"] with
             | Some b when String.lowercase_ascii b = "bridged" ->
                Bridge
             | Some _ | None -> Network in
           Some (port,
                 { s_mac = mac; s_nic_model = model;
                   s_vnet = vnet; s_vnet_orig = vnet;
                   s_vnet_type = vnet_type })
        | _ -> None
    ) nics in
  let nics = filter_map identity nics in

  (* Sort by port. *)
  let nics = List.sort compare nics in

  let nics = List.map (fun (_, source) -> source) nics in
  nics

class input_vmx vmx_filename = object
  inherit input

  method as_options = "-i vmx " ^ vmx_filename

  method source () =
    (* Parse the VMX file. *)
    let vmx = Parse_vmx.parse_file vmx_filename in

    let name =
      match Parse_vmx.get_string vmx ["displayName"] with
      | None ->
         warning (f_"no displayName key found in VMX file");
         name_from_disk vmx_filename
      | Some s -> s in

    let memory_mb =
      match Parse_vmx.get_int64 vmx ["memSize"] with
      | None -> 32_L            (* default is really 32 MB! *)
      | Some i -> i in
    let memory = memory_mb *^ 1024L *^ 1024L in

    let vcpu =
      match Parse_vmx.get_int vmx ["numvcpus"] with
      | None -> 1
      | Some i -> i in

    let firmware =
      match Parse_vmx.get_string vmx ["firmware"] with
      | None -> BIOS
      | Some "efi" -> UEFI
      (* Other values are not documented for this field ... *)
      | Some fw ->
         warning (f_"unknown firmware value '%s', assuming BIOS") fw;
         BIOS in

    let video =
      if Parse_vmx.namespace_present vmx ["svga"] then
        (* We could also parse svga.vramSize. *)
        Some (Source_other_video "vmvga")
      else
        None in

    let sound =
      match Parse_vmx.get_string vmx ["sound"; "virtualDev"] with
      | Some ("sb16") -> Some { s_sound_model = SB16 }
      | Some ("es1371") -> Some { s_sound_model = ES1370 (* hmmm ... *) }
      | Some "hdaudio" -> Some { s_sound_model = ICH6 (* intel-hda *) }
      | Some model ->
         warning (f_"unknown sound device '%s' ignored") model;
         None
      | None -> None in

    let disks = find_disks vmx vmx_filename in
    let removables = find_removables vmx in
    let nics = find_nics vmx in

    let source = {
      s_hypervisor = VMware;
      s_name = name;
      s_orig_name = name;
      s_memory = memory;
      s_vcpu = vcpu;
      s_features = [];
      s_firmware = firmware;
      s_display = None;
      s_video = video;
      s_sound = sound;
      s_disks = disks;
      s_removables = removables;
      s_nics = nics;
    } in

    source
end

let input_vmx = new input_vmx
let () = Modules_list.register_input_module "vmx"
