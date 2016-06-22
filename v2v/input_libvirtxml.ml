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

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

type parsed_disk = {
  p_source_disk : source_disk;
  p_source : parsed_source;
}
and parsed_source =
| P_source_dev of string
| P_source_file of string
| P_dont_rewrite

(* Turn string like "hda" into controller slot number.  See also
 * src/utils.c:guestfs_int_drive_index which this function calls.
 *)
let get_drive_slot str offset =
  let len = String.length str in
  if len-offset < 0 then
    failwith (sprintf "get_drive_slot: offset longer than string length (offset = %d, string = %s)" offset str);
  let name = String.sub str offset (len-offset) in
  try Some (drive_index name)
  with Invalid_argument _ ->
       warning (f_"could not parse device name '%s' from the source libvirt XML") str;
       None

let parse_libvirt_xml ?conn xml =
  debug "libvirt xml is:\n%s" xml;

  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx
  and xpath_int = xpath_int xpathctx
  and xpath_int_default = xpath_int_default xpathctx
  and xpath_int64_default = xpath_int64_default xpathctx in

  let hypervisor =
    match xpath_string "/domain/@type" with
    | None | Some "" ->
       error (f_"in the libvirt XML metadata, <domain type='...'> is missing or empty")
    | Some s -> source_hypervisor_of_string s in
  let name =
    match xpath_string "/domain/name/text()" with
    | None | Some "" ->
       error (f_"in the libvirt XML metadata, <name> is missing or empty")
    | Some s -> s in
  let memory = xpath_int64_default "/domain/memory/text()" (1024L *^ 1024L) in
  let memory = memory *^ 1024L in
  let vcpu = xpath_int_default "/domain/vcpu/text()" 1 in

  let features =
    let features = ref [] in
    let obj = Xml.xpath_eval_expression xpathctx "/domain/features/*" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node obj i in
      push_front (Xml.node_name node) features
    done;
    !features in

  let display =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/graphics" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    if nr_nodes < 1 then None
    else (
      (* Ignore everything except the first <graphics> device. *)
      let node = Xml.xpathobj_node obj 0 in
      Xml.xpathctx_set_current_context xpathctx node;
      let keymap = xpath_string "@keymap" in
      let password = xpath_string "@passwd" in
      let listen =
        let obj = Xml.xpath_eval_expression xpathctx "listen" in
        let nr_nodes = Xml.xpathobj_nr_nodes obj in
        if nr_nodes < 1 then (
          match xpath_string "@listen" with
          | None -> LNone | Some a -> LAddress a
        ) else (
          (* Use only the first <listen> configuration. *)
          match xpath_string "listen[1]/@type" with
          | None -> LNone
          | Some "address" ->
            (match xpath_string "listen[1]/@address" with
            | None -> LNone
            | Some a -> LAddress a
            )
          | Some "network" ->
            (match xpath_string "listen[1]/@network" with
            | None -> LNone
            | Some n -> LNetwork n
            )
          | Some t ->
            warning (f_"<listen type='%s'> in the input libvirt XML was ignored") t;
            LNone
        ) in
      let port =
        match xpath_string "@autoport" with
        | Some "no" ->
          (match xpath_int "@port" with
           | Some port when port > 0 -> Some port
           | Some _ | None -> None)
        | _ -> None in
      match xpath_string "@type" with
      | None -> None
      | Some "vnc" ->
        Some { s_display_type = VNC;
               s_keymap = keymap; s_password = password; s_listen = listen;
               s_port = port }
      | Some "spice" ->
        Some { s_display_type = Spice;
               s_keymap = keymap; s_password = password; s_listen = listen;
               s_port = port }
      | Some ("sdl"|"desktop" as t) ->
        warning (f_"virt-v2v does not support local displays, so <graphics type='%s'> in the input libvirt XML was ignored") t;
        None
      | Some t ->
        warning (f_"display <graphics type='%s'> in the input libvirt XML was ignored") t;
        None
    ) in

  (* Sound card. *)
  let sound =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/sound" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    if nr_nodes < 1 then None
    else (
      (* Ignore everything except the first <sound> device. *)
      let node = Xml.xpathobj_node obj 0 in

      Xml.xpathctx_set_current_context xpathctx node;
      match xpath_string "@model" with
      | None -> None
      | Some "ac97"   -> Some { s_sound_model = AC97 }
      | Some "es1370" -> Some { s_sound_model = ES1370 }
      | Some "ich6"   -> Some { s_sound_model = ICH6 }
      | Some "ich9"   -> Some { s_sound_model = ICH9 }
      | Some "pcspk"  -> Some { s_sound_model = PCSpeaker }
      | Some "sb16"   -> Some { s_sound_model = SB16 }
      | Some "usb"    -> Some { s_sound_model = USBAudio }
      | Some model ->
         warning (f_"unknown sound model %s ignored") model;
         None
    ) in

  (* Non-removable disk devices. *)
  let disks =
    let get_disks, add_disk =
      let disks = ref [] and i = ref 0 in
      let get_disks () = List.rev !disks in
      let add_disk qemu_uri format controller p_source =
        incr i;
        let disk = {
          p_source_disk = { s_disk_id = !i;
                            s_qemu_uri = qemu_uri;
                            s_format = format;
                            s_controller = controller };
          p_source = p_source
        } in
        push_front disk disks
      in
      get_disks, add_disk
    in
    let obj =
      Xml.xpath_eval_expression xpathctx
        "/domain/devices/disk[@device='disk']" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    if nr_nodes < 1 then
      error (f_"this guest has no non-removable disks");
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let controller =
        let target_bus = xpath_string "target/@bus" in
        match target_bus with
        | None -> None
        | Some "ide" -> Some Source_IDE
        | Some "scsi" -> Some Source_SCSI
        | Some "virtio" -> Some Source_virtio_blk
        | Some _ -> None in

      let format =
        match xpath_string "driver/@type" with
        | Some "aio" -> Some "raw" (* Xen wierdness *)
        | None -> None
        | Some format -> Some format in

      (* The <disk type='...'> attribute may be 'block', 'file',
       * 'network' or 'volume'.  We ignore any other types.
       *)
      match xpath_string "@type" with
      | None ->
         warning (f_"<disk> element with no type attribute ignored")
      | Some "block" ->
        (match xpath_string "source/@dev" with
         | Some path ->
            add_disk path format controller (P_source_dev path)
         | None -> ()
        );
      | Some "file" ->
        (match xpath_string "source/@file" with
         | Some path ->
            add_disk path format controller (P_source_file path)
         | None -> ()
        );
      | Some "network" ->
        (* We only handle <source protocol="nbd"> here, and that is
         * intended only for virt-p2v.
         *)
        (match (xpath_string "source/@protocol",
                xpath_string "source/host/@name",
                xpath_int "source/host/@port") with
        | None, _, _ ->
          warning (f_"<disk type=network> was ignored")
        | Some "nbd", Some ("localhost" as host), Some port when port > 0 ->
          (* virt-p2v: Generate a qemu nbd URL. *)
          let path = sprintf "nbd:%s:%d" host port in
          add_disk path format controller P_dont_rewrite
        | Some protocol, _, _ ->
          warning (f_"<disk type='network'> with <source protocol='%s'> was ignored")
            protocol
        )
      | Some "volume" ->
        (match xpath_string "source/@pool", xpath_string "source/@volume" with
        | None, None | Some _, None | None, Some _ -> ()
        | Some pool, Some vol ->
          let xml = Domainxml.vol_dumpxml ?conn pool vol in
          let doc = Xml.parse_memory xml in
          let xpathctx = Xml.xpath_new_context doc in
          let xpath_string = Utils.xpath_string xpathctx in

          (* Use the format specified in the volume itself. *)
          let format = xpath_string "/volume/target/format/@type" in

          (match xpath_string "/volume/@type" with
          | None | Some "file" ->
            (match xpath_string "/volume/target/path/text()" with
             | Some path ->
                add_disk path format controller (P_source_file path)
             | None -> ()
            );
          | Some vol_type ->
            warning (f_"<disk type='volume'> with <volume type='%s'> was ignored") vol_type
          )
        )
      | Some disk_type ->
        warning (f_"<disk type='%s'> was ignored") disk_type
    done;
    get_disks () in

  (* Removable devices, CD-ROMs and floppy disks. *)
  let removables =
    let obj =
      Xml.xpath_eval_expression xpathctx
        "/domain/devices/disk[@device='cdrom' or @device='floppy']" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    let disks = ref [] in
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let controller =
        let target_bus = xpath_string "target/@bus" in
        match target_bus with
        | None -> None
        | Some "ide" -> Some Source_IDE
        | Some "scsi" -> Some Source_SCSI
        | Some "virtio" -> Some Source_virtio_blk
        | Some _ -> None in

      let slot =
        let target_dev = xpath_string "target/@dev" in
        match target_dev with
        | None -> None
        | Some s when String.is_prefix s "hd" -> get_drive_slot s 2
        | Some s when String.is_prefix s "sd" -> get_drive_slot s 2
        | Some s when String.is_prefix s "vd" -> get_drive_slot s 2
        | Some s when String.is_prefix s "xvd" -> get_drive_slot s 3
        | Some s when String.is_prefix s "fd" -> get_drive_slot s 2
        | Some s ->
           warning (f_"<target dev='%s'> was ignored because the device name could not be recognized") s;
           None in

      let typ =
        match xpath_string "@device" with
        | Some "cdrom" -> CDROM
        | Some "floppy" -> Floppy
        | _ -> assert false (* libxml2 error? *) in

      let disk =
        { s_removable_type = typ;
          s_removable_controller = controller;
          s_removable_slot = slot } in
      push_front disk disks
    done;
    List.rev !disks in

  (* Network interfaces. *)
  let nics =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/interface" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    let nics = ref [] in
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let mac = xpath_string "mac/@address" in
      let mac =
        match mac with
        | None
        | Some "00:00:00:00:00:00" (* thanks, VMware *) -> None
        | Some mac -> Some mac in

      let vnet_type =
        match xpath_string "@type" with
        | Some "network" -> Some Network
        | Some "bridge" -> Some Bridge
        | None | Some _ -> None in
      match vnet_type with
      | None -> ()
      | Some vnet_type ->
         let add_nic vnet =
           let nic = {
             s_mac = mac;
             s_vnet = vnet;
             s_vnet_orig = vnet;
             s_vnet_type = vnet_type
           } in
           push_front nic nics
         in
         match xpath_string "source/@network | source/@bridge" with
         | None -> ()
         | Some "" ->
            (* The libvirt VMware driver produces at least <source
             * bridge=''/> XML - see RHBZ#1257895.
             *)
            add_nic (sprintf "eth%d" i)
         | Some vnet ->
            add_nic vnet
    done;
    List.rev !nics in

  ({
    s_hypervisor = hypervisor;
    s_name = name; s_orig_name = name;
    s_memory = memory;
    s_vcpu = vcpu;
    s_features = features;
    s_firmware = UnknownFirmware; (* XXX until RHBZ#1217444 is fixed *)
    s_display = display;
    s_sound = sound;
    s_disks = [];
    s_removables = removables;
    s_nics = nics;
   },
   disks)

class input_libvirtxml file =
object
  inherit input

  method as_options = "-i libvirtxml " ^ file

  method source () =
    let xml = read_whole_file file in

    let source, disks = parse_libvirt_xml xml in

    (* When reading libvirt XML from a file (-i libvirtxml) we allow
     * paths to disk images in the libvirt XML to be relative (to the XML
     * file).  Relative paths are in fact not permitted in real libvirt
     * XML, but they are very useful when dealing with test images or
     * when writing the XML by hand.
     *)
    let dir = Filename.dirname (absolute_path file) in
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } -> disk
      | { p_source_disk = disk; p_source = P_source_dev _ } -> disk
      | { p_source_disk = disk; p_source = P_source_file path } ->
        let path =
          if not (Filename.is_relative path) then path else dir // path in
        { disk with s_qemu_uri = path }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirtxml = new input_libvirtxml
let () = Modules_list.register_input_module "libvirtxml"
