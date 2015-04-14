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

let parse_libvirt_xml ~verbose xml =
  if verbose then
    printf "libvirt xml is:\n%s\n" xml;

  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in

  let xpath_to_string expr default =
    let obj = Xml.xpath_eval_expression xpathctx expr in
    if Xml.xpathobj_nr_nodes obj < 1 then default
    else (
      let node = Xml.xpathobj_node doc obj 0 in
      Xml.node_as_string node
    )
  and xpath_to_int expr default =
    let obj = Xml.xpath_eval_expression xpathctx expr in
    if Xml.xpathobj_nr_nodes obj < 1 then default
    else (
      let node = Xml.xpathobj_node doc obj 0 in
      let str = Xml.node_as_string node in
      try int_of_string str
      with Failure "int_of_string" ->
        error (f_"expecting XML expression to return an integer (expression: %s)")
          expr
    )
  in

  let dom_type = xpath_to_string "/domain/@type" "" in
  let name = xpath_to_string "/domain/name/text()" "" in
  let memory = xpath_to_int "/domain/memory/text()" (1024 * 1024) in
  let memory = Int64.of_int memory *^ 1024L in
  let vcpu = xpath_to_int "/domain/vcpu/text()" 1 in

  if dom_type = "" then
    error (f_"in the libvirt XML metadata, <domain type='...'> is missing or empty");
  if name = "" then
    error (f_"in the libvirt XML metadata, <name> is missing or empty");

  let features =
    let features = ref [] in
    let obj = Xml.xpath_eval_expression xpathctx "/domain/features/*" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node doc obj i in
      features := Xml.node_name node :: !features
    done;
    !features in

  let display =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/graphics" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    if nr_nodes < 1 then None
    else (
      (* Ignore everything except the first <graphics> device. *)
      let node = Xml.xpathobj_node doc obj 0 in
      Xml.xpathctx_set_current_context xpathctx node;
      let keymap =
        match xpath_to_string "@keymap" "" with "" -> None | k -> Some k in
      let password =
        match xpath_to_string "@passwd" "" with "" -> None | pw -> Some pw in
      let listen =
        let obj = Xml.xpath_eval_expression xpathctx "listen" in
        let nr_nodes = Xml.xpathobj_nr_nodes obj in
        if nr_nodes < 1 then LNone
        else (
          (* Use only the first <listen> configuration. *)
          match xpath_to_string "listen[1]/@type" "" with
          | "" -> LNone
          | "address" ->
            (match xpath_to_string "listen[1]/@address" "" with
            | "" -> LNone
            | a -> LAddress a
            )
          | "network" ->
            (match xpath_to_string "listen[1]/@network" "" with
            | "" -> LNone
            | n -> LNetwork n
            )
          | t ->
            warning ~prog (f_"<listen type='%s'> in the input libvirt XML was ignored") t;
            LNone
        ) in
      let port =
        match xpath_to_string "@autoport" "yes" with
        | "no" ->
          let port = xpath_to_int "@port" (-1) in
          if port >= 0 then Some port
          else None
        | _ -> None in
      match xpath_to_string "@type" "" with
      | "" -> None
      | "vnc" ->
        Some { s_display_type = VNC;
               s_keymap = keymap; s_password = password; s_listen = listen;
               s_port = port }
      | "spice" ->
        Some { s_display_type = Spice;
               s_keymap = keymap; s_password = password; s_listen = listen;
               s_port = port }
      | "sdl"|"desktop" as t ->
        warning ~prog (f_"virt-v2v does not support local displays, so <graphics type='%s'> in the input libvirt XML was ignored") t;
        None
      | t ->
        warning ~prog (f_"display <graphics type='%s'> in the input libvirt XML was ignored") t;
        None
    ) in

  (* Non-removable disk devices. *)
  let disks =
    let get_disks, add_disk =
      let disks = ref [] and i = ref 0 in
      let get_disks () = List.rev !disks in
      let add_disk qemu_uri format controller p_source =
        incr i;
        disks :=
          { p_source_disk = { s_disk_id = !i;
                              s_qemu_uri = qemu_uri; s_format = format;
                              s_controller = controller };
            p_source = p_source } :: !disks
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
      let node = Xml.xpathobj_node doc obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let controller =
        let target_bus = xpath_to_string "target/@bus" "" in
        match target_bus with
        | "" -> None
        | "ide" -> Some Source_IDE
        | "scsi" -> Some Source_SCSI
        | "virtio" -> Some Source_virtio_blk
        | _ -> None in

      let format =
        match xpath_to_string "driver/@type" "" with
        | "aio" -> Some "raw" (* Xen wierdness *)
        | "" -> None
        | format -> Some format in

      (* The <disk type='...'> attribute may be 'block', 'file' or
       * 'network'.  We ignore any other types.
       *)
      match xpath_to_string "@type" "" with
      | "block" ->
        let path = xpath_to_string "source/@dev" "" in
        if path <> "" then
          add_disk path format controller (P_source_dev path)
      | "file" ->
        let path = xpath_to_string "source/@file" "" in
        if path <> "" then
          add_disk path format controller (P_source_file path)
      | "network" ->
        (* We only handle <source protocol="nbd"> here, and that is
         * intended only for virt-p2v.  Any other network disk is
         * currently ignored.
         *)
        (match xpath_to_string "source/@protocol" "" with
        | "nbd" ->
          let host = xpath_to_string "source/host/@name" "" in
          let port = xpath_to_int "source/host/@port" 0 in
          if host <> "" && port > 0 then (
            (* Generate a qemu nbd URL.
             * XXX Quoting, although it's not needed for virt-p2v.
             *)
            let path = sprintf "nbd:%s:%d" host port in
            add_disk path format controller P_dont_rewrite
          )
        | "" -> ()
        | protocol ->
          warning ~prog (f_"network <disk> with <source protocol='%s'> was ignored")
            protocol
        )
      | disk_type ->
        warning ~prog (f_"<disk type='%s'> was ignored") disk_type
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
      let node = Xml.xpathobj_node doc obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let controller =
        let target_bus = xpath_to_string "target/@bus" "" in
        match target_bus with
        | "" -> None
        | "ide" -> Some Source_IDE
        | "scsi" -> Some Source_SCSI
        | "virtio" -> Some Source_virtio_blk
        | _ -> None in

      let typ =
        match xpath_to_string "@device" "" with
        | "cdrom" -> CDROM
        | "floppy" -> Floppy
        | _ -> assert false (* libxml2 error? *) in

      let disk =
        { s_removable_type = typ; s_removable_controller = controller } in
      disks := disk :: !disks
    done;
    List.rev !disks in

  (* Network interfaces. *)
  let nics =
    let obj = Xml.xpath_eval_expression xpathctx "/domain/devices/interface" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    let nics = ref [] in
    for i = 0 to nr_nodes-1 do
      let node = Xml.xpathobj_node doc obj i in
      Xml.xpathctx_set_current_context xpathctx node;

      let mac = xpath_to_string "mac/@address" "" in
      let mac =
        match mac with
        | ""
        | "00:00:00:00:00:00" (* thanks, VMware *) -> None
        | mac -> Some mac in

      let vnet_type =
        match xpath_to_string "@type" "" with
        | "network" -> Some Network
        | "bridge" -> Some Bridge
        | _ -> None in
      match vnet_type with
      | None -> ()
      | Some vnet_type ->
        let vnet = xpath_to_string "source/@network | source/@bridge" "" in
        if vnet <> "" then (
          let nic = {
            s_mac = mac;
            s_vnet = vnet;
            s_vnet_orig = vnet;
            s_vnet_type = vnet_type
          } in
          nics := nic :: !nics
        )
    done;
    List.rev !nics in

  ({
    s_dom_type = dom_type;
    s_name = name; s_orig_name = name;
    s_memory = memory;
    s_vcpu = vcpu;
    s_features = features;
    s_display = display;
    s_disks = [];
    s_removables = removables;
    s_nics = nics;
   },
   disks)

class input_libvirtxml verbose file =
object
  inherit input verbose

  method as_options = "-i libvirtxml " ^ file

  method source () =
    let xml = read_whole_file file in

    let source, disks = parse_libvirt_xml ~verbose xml in

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
