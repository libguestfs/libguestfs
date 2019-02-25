(* virt-v2v
 * Copyright (C) 2019 Red Hat Inc.
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

open Std_utils
open C_utils
open Tools_utils

open Types
open Utils

module G = Guestfs

let json_list_of_string_list =
  List.map (fun x -> JSON.String x)

let json_list_of_string_string_list =
  List.map (fun (x, y) -> x, JSON.String y)

let push_optional_string lst name = function
  | None -> ()
  | Some v -> List.push_back lst (name, JSON.String v)

let push_optional_int lst name = function
  | None -> ()
  | Some v -> List.push_back lst (name, JSON.Int (Int64.of_int v))

let json_unknown_string = function
  | "unknown" -> JSON.Null
  | v -> JSON.String v

let find_target_disk targets { s_disk_id = id } =
  try List.find (fun t -> t.target_overlay.ov_source.s_disk_id = id) targets
  with Not_found -> assert false

let create_json_metadata source targets target_buses
                         guestcaps inspect target_firmware =
  let doc = ref [
    "version", JSON.Int 1L;
    "name", JSON.String source.s_name;
    "memory", JSON.Int source.s_memory;
    "vcpu", JSON.Int (Int64.of_int source.s_vcpu);
  ] in

  (match source.s_genid with
   | None -> ()
   | Some genid -> List.push_back doc ("genid", JSON.String genid)
  );

  if source.s_cpu_vendor <> None || source.s_cpu_model <> None ||
     source.s_cpu_topology <> None then (
    let cpu = ref [] in

    push_optional_string cpu "vendor" source.s_cpu_vendor;
    push_optional_string cpu "model" source.s_cpu_model;
    (match source.s_cpu_topology with
     | None -> ()
     | Some { s_cpu_sockets; s_cpu_cores; s_cpu_threads } ->
        let attrs = [
          "sockets", JSON.Int (Int64.of_int s_cpu_sockets);
          "cores", JSON.Int (Int64.of_int s_cpu_cores);
          "threads", JSON.Int (Int64.of_int s_cpu_threads);
        ] in
        List.push_back cpu ("topology", JSON.Dict attrs)
    );

    List.push_back doc ("cpu", JSON.Dict !cpu);
  );

  let firmware =
    let firmware_type =
      match target_firmware with
      | TargetBIOS -> "bios"
      | TargetUEFI -> "uefi" in

    let fw = ref [
      "type", JSON.String firmware_type;
    ] in

    (match target_firmware with
     | TargetBIOS -> ()
     | TargetUEFI ->
       let uefi_firmware = find_uefi_firmware guestcaps.gcaps_arch in
       let flags =
         List.map (
           function
           | Uefi.UEFI_FLAG_SECURE_BOOT_REQUIRED -> "secure_boot_required"
         ) uefi_firmware.Uefi.flags in

       let uefi = ref [
         "code", JSON.String uefi_firmware.Uefi.code;
         "vars", JSON.String uefi_firmware.Uefi.vars;
         "flags", JSON.List (json_list_of_string_list flags);
       ] in

       push_optional_string uefi "code-debug" uefi_firmware.Uefi.code_debug;

       List.push_back fw ("uefi", JSON.Dict !uefi)
    );

    !fw in
  List.push_back doc ("firmware", JSON.Dict firmware);

  List.push_back doc ("features",
                      JSON.List (json_list_of_string_list source.s_features));

  let machine =
    match guestcaps.gcaps_machine with
    | I440FX -> "pc"
    | Q35 -> "q35"
    | Virt -> "virt" in
  List.push_back doc ("machine", JSON.String machine);

  let disks, removables =
    let disks = ref []
    and removables = ref [] in

    let iter_bus bus_name drive_prefix i = function
    | BusSlotEmpty -> ()
    | BusSlotDisk d ->
       (* Find the corresponding target disk. *)
       let t = find_target_disk targets d in

       let target_file =
         match t.target_file with
         | TargetFile s -> s
         | TargetURI _ -> assert false in

       let disk = [
         "dev", JSON.String (drive_prefix ^ drive_name i);
         "bus", JSON.String bus_name;
         "format", JSON.String t.target_format;
         "file", JSON.String (absolute_path target_file);
       ] in

       List.push_back disks (JSON.Dict disk)

    | BusSlotRemovable { s_removable_type = CDROM } ->
       let cdrom = [
         "type", JSON.String "cdrom";
         "dev", JSON.String (drive_prefix ^ drive_name i);
         "bus", JSON.String bus_name;
       ] in

       List.push_back removables (JSON.Dict cdrom)

    | BusSlotRemovable { s_removable_type = Floppy } ->
       let floppy = [
         "type", JSON.String "floppy";
         "dev", JSON.String (drive_prefix ^ drive_name i);
       ] in

       List.push_back removables (JSON.Dict floppy)
    in

    Array.iteri (iter_bus "virtio" "vd") target_buses.target_virtio_blk_bus;
    Array.iteri (iter_bus "ide" "hd") target_buses.target_ide_bus;
    Array.iteri (iter_bus "scsi" "sd") target_buses.target_scsi_bus;
    Array.iteri (iter_bus "floppy" "fd") target_buses.target_floppy_bus;

    !disks, !removables in
  List.push_back doc ("disks", JSON.List disks);
  List.push_back doc ("removables", JSON.List removables);

  let nics =
    List.map (
      fun { s_mac = mac; s_vnet_type = vnet_type; s_nic_model = nic_model;
            s_vnet = vnet; } ->
        let vnet_type_str =
          match vnet_type with
          | Bridge -> "bridge"
          | Network -> "network" in

        let nic = ref [
          "vnet", JSON.String vnet;
          "vnet-type", JSON.String vnet_type_str;
        ] in

        let nic_model_str = Option.map string_of_nic_model nic_model in
        push_optional_string nic "model" nic_model_str;

        push_optional_string nic "mac" mac;

        JSON.Dict !nic
    ) source.s_nics in
  List.push_back doc ("nics", JSON.List nics);

  let guestcaps_dict =
    let block_bus =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk -> "virtio-blk"
      | Virtio_SCSI -> "virtio-scsi"
      | IDE -> "ide" in
    let net_bus =
      match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio-net"
      | E1000 -> "e1000"
      | RTL8139 -> "rtl8139" in
    let video =
      match guestcaps.gcaps_video with
      | QXL -> "qxl"
      | Cirrus -> "cirrus" in
    let machine =
      match guestcaps.gcaps_machine with
      | I440FX -> "i440fx"
      | Q35 -> "q35"
      | Virt -> "virt" in

    [
      "block-bus", JSON.String block_bus;
      "net-bus", JSON.String net_bus;
      "video", JSON.String video;
      "machine", JSON.String machine;
      "arch", JSON.String guestcaps.gcaps_arch;
      "virtio-rng", JSON.Bool guestcaps.gcaps_virtio_rng;
      "virtio-balloon", JSON.Bool guestcaps.gcaps_virtio_balloon;
      "isa-pvpanic", JSON.Bool guestcaps.gcaps_isa_pvpanic;
      "acpi", JSON.Bool guestcaps.gcaps_acpi;
    ] in
  List.push_back doc ("guestcaps", JSON.Dict guestcaps_dict);

  (match source.s_sound with
   | None -> ()
   | Some { s_sound_model = model } ->
     let sound = [
       "model", JSON.String (string_of_source_sound_model model);
     ] in
     List.push_back doc ("sound", JSON.Dict sound)
   );

  (match source.s_display with
   | None -> ()
   | Some d ->
     let display_type =
       match d.s_display_type with
       | Window -> "window"
       | VNC -> "vnc"
       | Spice -> "spice" in

     let display = ref [
       "type", JSON.String display_type;
     ] in

     push_optional_string display "keymap" d.s_keymap;
     push_optional_string display "password" d.s_password;

     let listen =
       match d.s_listen with
       | LNoListen -> None
       | LAddress address ->
         Some [
           "type", JSON.String "address";
           "address", JSON.String address;
         ]
       | LNetwork network ->
         Some [
           "type", JSON.String "network";
           "network", JSON.String network;
         ]
       | LSocket None ->
         Some [
           "type", JSON.String "socket";
           "socket", JSON.Null;
         ]
       | LSocket (Some socket) ->
         Some [
           "type", JSON.String "socket";
           "socket", JSON.String socket;
         ]
       | LNone ->
         Some [
           "type", JSON.String "none";
         ] in
     (match listen with
      | None -> ()
      | Some l -> List.push_back display ("listen", JSON.Dict l)
     );

     push_optional_int display "port" d.s_port;

     List.push_back doc ("display", JSON.Dict !display)
  );

  let inspect_dict =
    let apps =
      List.map (
        fun { G.app2_name = name; app2_display_name = display_name;
              app2_epoch = epoch; app2_version = version;
              app2_release = release; app2_arch = arch; } ->
          JSON.Dict [
            "name", JSON.String name;
            "display-name", JSON.String display_name;
            "epoch", JSON.Int (Int64.of_int32 epoch);
            "version", JSON.String version;
            "release", JSON.String release;
            "arch", JSON.String arch;
          ]
      ) inspect.i_apps in

    let firmware_dict =
      match inspect.i_firmware with
      | I_BIOS ->
        [
          "type", JSON.String "bios";
        ]
      | I_UEFI devices ->
        [
          "type", JSON.String "uefi";
          "devices", JSON.List (json_list_of_string_list devices);
        ] in

    [
      "root", JSON.String inspect.i_root;
      "type", JSON.String inspect.i_type;
      "distro", json_unknown_string inspect.i_distro;
      "osinfo", json_unknown_string inspect.i_osinfo;
      "arch", JSON.String inspect.i_arch;
      "major-version", JSON.Int (Int64.of_int inspect.i_major_version);
      "minor-version", JSON.Int (Int64.of_int inspect.i_minor_version);
      "package-format", json_unknown_string inspect.i_package_format;
      "package-management", json_unknown_string inspect.i_package_management;
      "product-name", json_unknown_string inspect.i_product_name;
      "product-variant", json_unknown_string inspect.i_product_variant;
      "mountpoints", JSON.Dict (json_list_of_string_string_list inspect.i_mountpoints);
      "applications", JSON.List apps;
      "windows-systemroot", JSON.String inspect.i_windows_systemroot;
      "windows-software-hive", JSON.String inspect.i_windows_software_hive;
      "windows-system-hive", JSON.String inspect.i_windows_system_hive;
      "windows-current-control-set", JSON.String inspect.i_windows_current_control_set;
      "firmware", JSON.Dict firmware_dict;
    ] in
  List.push_back doc ("inspect", JSON.Dict inspect_dict);

  !doc
