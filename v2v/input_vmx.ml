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

open Unix_utils
open Common_gettext.Gettext
open Common_utils

open Types
open Utils
open Name_from_disk

type vmx_source =
  | File of string              (* local file or NFS *)
  | SSH of Xml.uri              (* SSH URI *)

(* The single filename on the command line is intepreted either as
 * a local file or a remote SSH URI (only if ‘-it ssh’).
 *)
let vmx_source_of_arg input_transport arg =
  match input_transport, arg with
  | None, arg -> File arg
  | Some `SSH, arg ->
     let uri =
       try Xml.parse_uri arg
       with Invalid_argument _ ->
         error (f_"remote vmx ‘%s’ could not be parsed as a URI") arg in
     if uri.Xml.uri_scheme <> None && uri.Xml.uri_scheme <> Some "ssh" then
       error (f_"vmx URI start with ‘ssh://...’");
     if uri.Xml.uri_server = None then
       error (f_"vmx URI remote server name omitted");
     if uri.Xml.uri_path = None || uri.Xml.uri_path = Some "/" then
       error (f_"vmx URI path component looks incorrect");
     SSH uri

(* Return various fields from the URI.  The checks in vmx_source_of_arg
 * should ensure that none of these assertions fail.
 *)
let port_of_uri { Xml.uri_port } =
  match uri_port with i when i <= 0 -> None | i -> Some i
let server_of_uri { Xml.uri_server } =
  match uri_server with None -> assert false | Some s -> s
let path_of_uri { Xml.uri_path } =
  match uri_path with None -> assert false | Some p -> p

(* 'scp' a remote file into a temporary local file, returning the path
 * of the temporary local file.
 *)
let scp_from_remote_to_temporary uri tmpdir filename =
  let localfile = tmpdir // filename in

  let cmd =
    sprintf "scp%s%s %s%s:%s %s"
            (if verbose () then "" else " -q")
            (match port_of_uri uri with
             | None -> ""
             | Some port -> sprintf " -P %d" port)
            (match uri.Xml.uri_user with
             | None -> ""
             | Some user -> quote user ^ "@")
            (quote (server_of_uri uri))
            (* The double quoting of the path is counter-intuitive
             * but correct, see:
             * https://stackoverflow.com/questions/19858176/how-to-escape-spaces-in-path-during-scp-copy-in-linux
             *)
            (quote (quote (path_of_uri uri)))
            (quote localfile) in
  if verbose () then
    eprintf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    error (f_"could not copy the VMX file from the remote server, see earlier error messages");
  localfile

(* Test if [path] exists on the remote server. *)
let remote_file_exists uri path =
  let cmd =
    sprintf "ssh%s %s%s test -f %s"
            (match port_of_uri uri with
             | None -> ""
             | Some port -> sprintf " -p %d" port)
            (match uri.Xml.uri_user with
             | None -> ""
             | Some user -> quote user ^ "@")
            (quote (server_of_uri uri))
            (* Double quoting is necessary here, see above. *)
            (quote (quote path)) in
  if verbose () then
    eprintf "%s\n%!" cmd;
  Sys.command cmd = 0

let rec find_disks vmx vmx_source =
  find_scsi_disks vmx vmx_source @ find_ide_disks vmx vmx_source

(* Find all SCSI hard disks.
 *
 * In the VMX file:
 *   scsi0.virtualDev = "pvscsi"  # or may be "lsilogic" etc.
 *   scsi0:0.deviceType = "disk" | "plainDisk" | "rawDisk" | "scsi-hardDisk"
 *                        | omitted
 *   scsi0:0.fileName = "guest.vmdk"
 *)
and find_scsi_disks vmx vmx_source =
  let get_scsi_controller_target ns =
    sscanf ns "scsi%d:%d" (fun c t -> c, t)
  in
  let is_scsi_controller_target ns =
    try ignore (get_scsi_controller_target ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in
  let scsi_device_types = [ Some "disk"; Some "plaindisk"; Some "rawdisk";
                            Some "scsi-harddisk"; None ] in
  let scsi_controller = Source_SCSI in

  find_hdds vmx vmx_source
            get_scsi_controller_target is_scsi_controller_target
            scsi_device_types scsi_controller

(* Find all IDE hard disks.
 *
 * In the VMX file:
 *   ide0:0.deviceType = "ata-hardDisk"
 *   ide0:0.fileName = "guest.vmdk"
 *)
and find_ide_disks vmx vmx_source =
  let get_ide_controller_target ns =
    sscanf ns "ide%d:%d" (fun c t -> c, t)
  in
  let is_ide_controller_target ns =
    try ignore (get_ide_controller_target ns); true
    with Scanf.Scan_failure _ | End_of_file | Failure _ -> false
  in
  let ide_device_types = [ Some "ata-harddisk" ] in
  let ide_controller = Source_IDE in

  find_hdds vmx vmx_source
            get_ide_controller_target is_ide_controller_target
            ide_device_types ide_controller

and find_hdds vmx vmx_source
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
           let dt = Parse_vmx.get_string vmx [ns; "deviceType"] in
           let dt =
             match dt with
             | None -> None
             | Some dt -> Some (String.lowercase_ascii dt) in
           List.mem dt device_types
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
           let uri, format = qemu_uri_of_filename vmx_source filename in
           let s = { s_disk_id = (-1);
                     s_qemu_uri = uri; s_format = Some format;
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
 * This constructs a QEMU URI of the filename relative to the
 * vmx file (which might be remote over SSH).
 *)
and qemu_uri_of_filename vmx_source filename =
  match vmx_source with
  | File vmx_filename ->
     (* Always ensure this returns an absolute path to avoid
      * any confusion with filenames containing colons.
      *)
     absolute_path_from_other_file vmx_filename filename, "vmdk"

  | SSH uri ->
     let vmx_path = path_of_uri uri in
     let abs_path = absolute_path_from_other_file vmx_path filename in
     let format = "vmdk" in

     (* XXX This is a hack to work around qemu / VMDK limitation
      *   "Cannot use relative extent paths with VMDK descriptor file"
      * We can remove this if the above is fixed.
      *)
     let abs_path, format =
       let flat_vmdk =
         Str.replace_first (Str.regexp "\\.vmdk$") "-flat.vmdk" abs_path in
       if remote_file_exists uri flat_vmdk then (flat_vmdk, "raw")
       else (abs_path, format) in

     let json_params = [
       "file.driver", JSON.String "ssh";
       "file.path", JSON.String abs_path;
       "file.host", JSON.String (server_of_uri uri);
       "file.host_key_check", JSON.String "no";
     ] in
     let json_params =
       match uri.Xml.uri_user with
       | None -> json_params
       | Some user ->
          ("file.user", JSON.String user) :: json_params in
     let json_params =
       match port_of_uri uri with
       | None -> json_params
       | Some port ->
          ("file.port", JSON.Int port) :: json_params in

     "json:" ^ JSON.string_of_doc json_params, format

and absolute_path_from_other_file other_filename filename =
  if not (Filename.is_relative filename) then filename
  else (Filename.dirname (absolute_path other_filename)) // filename

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

class input_vmx input_transport arg =
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "vmx." in
    rmdir_on_exit t;
    t in
object
  inherit input

  method as_options = "-i vmx " ^ arg

  method precheck () =
    match input_transport with
    | None -> ()
    | Some `SSH ->
       if backend_is_libvirt () then
         error (f_"because libvirtd doesn't pass the SSH_AUTH_SOCK environment variable to qemu you must set this environment variable:\n\nexport LIBGUESTFS_BACKEND=direct\n\nand then rerun the virt-v2v command.");
       error_if_no_ssh_agent ()

  method source () =
    let vmx_source = vmx_source_of_arg input_transport arg in

    (* If the transport is SSH, fetch the file from remote, else
     * parse it from local.
     *)
    let vmx =
      match vmx_source with
      | File filename -> Parse_vmx.parse_file filename
      | SSH uri ->
         let filename = scp_from_remote_to_temporary uri tmpdir "source.vmx" in
         Parse_vmx.parse_file filename in

    let name =
      match Parse_vmx.get_string vmx ["displayName"] with
      | Some s -> s
      | None ->
         warning (f_"no displayName key found in VMX file");
         match vmx_source with
         | File filename -> name_from_disk filename
         | SSH uri -> name_from_disk (path_of_uri uri) in

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

    let disks = find_disks vmx vmx_source in
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
