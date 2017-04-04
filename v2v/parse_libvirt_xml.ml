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

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Xpath_helpers

type parsed_disk = {
  p_source_disk : source_disk;
  p_source : parsed_source;
}
and parsed_source =
| P_source_dev of string
| P_source_file of string
| P_dont_rewrite

(* Turn string like "hda" into controller slot number.  See also
 * common/utils/utils.c:guestfs_int_drive_index which this function calls.
 *)
let get_drive_slot str offset =
  let name = String.sub str offset (String.length str - offset) in
  try Some (Utils.drive_index name)
  with Invalid_argument _ ->
       warning (f_"could not parse device name ‘%s’ from the source libvirt XML") str;
       None

let parse_libvirt_xml ?conn xml =
  debug "libvirt xml is:\n%s" xml;

  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx
  and xpath_int = xpath_int xpathctx
  (*and xpath_int_default = xpath_int_default xpathctx*)
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

  let cpu_vendor = xpath_string "/domain/cpu/vendor/text()" in
  let cpu_model = xpath_string "/domain/cpu/model/text()" in
  let cpu_sockets = xpath_int "/domain/cpu/topology/@sockets" in
  let cpu_cores = xpath_int "/domain/cpu/topology/@cores" in
  let cpu_threads = xpath_int "/domain/cpu/topology/@threads" in

  (* Get the <vcpu> field from the input XML.  If not set then
   * try calculating it from the <cpu> <topology> node.  If that's
   * not set either, then assume 1 vCPU.
   *)
  let vcpu = xpath_int "/domain/vcpu/text()" in
  let vcpu =
    match vcpu, cpu_sockets, cpu_cores, cpu_threads with
    | Some vcpu, _,    _,    _    -> vcpu
    | None,      None, None, None -> 1
    | None,      _,    _,    _    ->
       let sockets = match cpu_sockets with None -> 1 | Some v -> v in
       let cores = match cpu_cores with None -> 1 | Some v -> v in
       let threads = match cpu_threads with None -> 1 | Some v -> v in
       sockets * cores * threads in

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
          | None -> LNoListen | Some a -> LAddress a
        ) else (
          (* Use only the first <listen> configuration. *)
          match xpath_string "listen[1]/@type" with
          | None -> LNoListen
          | Some "address" ->
            (match xpath_string "listen[1]/@address" with
            | None -> LNoListen
            | Some a -> LAddress a
            )
          | Some "network" ->
            (match xpath_string "listen[1]/@network" with
            | None -> LNoListen
            | Some n -> LNetwork n
            )
          | Some "socket" ->
            (match xpath_string "listen[1]/@socket" with
            | None -> LSocket None
            | Some n -> LSocket (Some n)
            )
          | Some "none" ->
            LNone
          | Some t ->
            warning (f_"<listen type='%s'> in the input libvirt XML was ignored") t;
            LNoListen
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

  (* Video adapter. *)
  let video =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/video" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    if nr_nodes < 1 then None
    else (
      (* Ignore everything except the first <video> device. *)
      let node = Xml.xpathobj_node obj 0 in

      Xml.xpathctx_set_current_context xpathctx node;
      match xpath_string "model/@type" with
      | None -> None
      | Some "qxl" | Some "virtio" -> Some Source_QXL
      | Some "cirrus" | Some "vga" -> Some Source_Cirrus
      | Some model -> Some (Source_other_video model)
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

  (* Presence of virtio-scsi controller. *)
  let has_virtio_scsi =
    let obj = Xml.xpath_eval_expression xpathctx
                "/domain/devices/controller[@model='virtio-scsi']" in
    Xml.xpathobj_nr_nodes obj > 0 in

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
        match target_bus, has_virtio_scsi with
        | None, _ -> None
        | Some "ide", _ -> Some Source_IDE
        | Some "scsi", true -> Some Source_virtio_SCSI
        | Some "scsi", false -> Some Source_SCSI
        | Some "virtio", _ -> Some Source_virtio_blk
        | Some _, _ -> None in

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
          warning (f_"<disk type='%s'> was ignored") "network"
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
          let xml = Libvirt_utils.vol_dumpxml ?conn pool vol in
          let doc = Xml.parse_memory xml in
          let xpathctx = Xml.xpath_new_context doc in
          let xpath_string = Xpath_helpers.xpath_string xpathctx in

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
        match target_bus, has_virtio_scsi with
        | None, _ -> None
        | Some "ide", _ -> Some Source_IDE
        | Some "scsi", true -> Some Source_virtio_SCSI
        | Some "scsi", false -> Some Source_SCSI
        | Some "virtio", _ -> Some Source_virtio_blk
        | Some _, _ -> None in

      let slot =
        let target_dev = xpath_string "target/@dev" in
        match target_dev with
        | None -> None
        | Some dev ->
           let rec loop = function
             | [] ->
                warning (f_"<target dev='%s'> was ignored because the device name could not be recognized") dev;
                None
             | prefix :: rest ->
                if String.is_prefix dev prefix then (
                  let offset = String.length prefix in
                  get_drive_slot dev offset
                )
                else
                  loop rest
           in
           loop ["hd"; "sd"; "vd"; "xvd"; "fd"] in

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

      let model =
        match xpath_string "model/@type" with
        | None -> None
        | Some "virtio" -> Some Source_virtio_net
        | Some "e1000" -> Some Source_e1000
        | Some "rtl8139" -> Some Source_rtl8139
        | Some model -> Some (Source_other_nic model) in

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
             s_nic_model = model;
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
    s_cpu_vendor = cpu_vendor;
    s_cpu_model = cpu_model;
    s_cpu_sockets = cpu_sockets;
    s_cpu_cores = cpu_cores;
    s_cpu_threads = cpu_threads;
    s_features = features;
    s_firmware = UnknownFirmware; (* XXX until RHBZ#1217444 is fixed *)
    s_display = display;
    s_video = video;
    s_sound = sound;
    s_disks = [];
    s_removables = removables;
    s_nics = nics;
   },
   disks)
