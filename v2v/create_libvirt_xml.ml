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

open Std_utils
open C_utils
open Common_utils
open Common_gettext.Gettext

open Types
open Utils
open DOM

let string_set_of_list =
  List.fold_left (fun set x -> StringSet.add x set) StringSet.empty

let create_libvirt_xml ?pool source target_buses guestcaps
                       target_features target_firmware =
  (* The main body of the libvirt XML document. *)
  let body = ref [] in

  append body [
    Comment generated_by;
    e "name" [] [PCData source.s_name];
  ];

  let memory_k = source.s_memory /^ 1024L in
  append body [
    e "memory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
    e "currentMemory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
    e "vcpu" [] [PCData (string_of_int source.s_vcpu)]
  ];

  if source.s_cpu_vendor <> None || source.s_cpu_model <> None ||
     source.s_cpu_sockets <> None || source.s_cpu_cores <> None ||
     source.s_cpu_threads <> None then (
    let cpu = ref [] in

    (match source.s_cpu_vendor with
     | None -> ()
     | Some vendor ->
        push_back cpu (e "vendor" [] [PCData vendor])
    );
    (match source.s_cpu_model with
     | None -> ()
     | Some model ->
        push_back cpu (e "model" ["fallback", "allow"] [PCData model])
    );
    if source.s_cpu_sockets <> None || source.s_cpu_cores <> None ||
       source.s_cpu_threads <> None then (
      let topology_attrs = ref [] in
      (match source.s_cpu_sockets with
       | None -> ()
       | Some v -> push_back topology_attrs ("sockets", string_of_int v)
      );
      (match source.s_cpu_cores with
       | None -> ()
       | Some v -> push_back topology_attrs ("cores", string_of_int v)
      );
      (match source.s_cpu_threads with
       | None -> ()
       | Some v -> push_back topology_attrs ("threads", string_of_int v)
      );
      push_back cpu (e "topology" !topology_attrs [])
    );

    append body [ e "cpu" [ "match", "minimum" ] !cpu ]
  );

  let uefi_firmware =
    match target_firmware with
    | TargetBIOS -> None
    | TargetUEFI -> Some (find_uefi_firmware guestcaps.gcaps_arch) in
  let secure_boot_required =
    match uefi_firmware with
    | Some { Uefi.flags = flags }
         when List.mem Uefi.UEFI_FLAG_SECURE_BOOT_REQUIRED flags -> true
    | _ -> false in
  (* Currently these are required by secure boot, but in theory they
   * might be independent properties.
   *)
  let machine_q35 = secure_boot_required in
  let smm = secure_boot_required in

  (* We have the machine features of the guest when it was on the
   * source hypervisor (source.s_features).  We have the acpi flag
   * which tells us whether acpi is required by this guest
   * (guestcaps.gcaps_acpi).  And we have the set of hypervisor
   * features supported by the target (target_features).  Combine all
   * this into a final list of features.
   *)
  let features = string_set_of_list source.s_features in
  let target_features = string_set_of_list target_features in

  (* If the guest supports ACPI, add it to the output XML.  Conversely
   * if the guest does not support ACPI, then we must drop it.
   * (RHBZ#1159258)
   *)
  let features =
    if guestcaps.gcaps_acpi then
      StringSet.add "acpi" features
    else
      StringSet.remove "acpi" features in

  (* Make sure we don't add any features which are not supported by
   * the target hypervisor.
   *)
  let features = StringSet.inter(*section*) features target_features in

  (* But if the target supports apic or pae then we should add them
   * anyway (old virt-v2v did this).
   *)
  let force_features = string_set_of_list ["apic"; "pae"] in
  let force_features =
    StringSet.inter(*section*) force_features target_features in
  let features = StringSet.union features force_features in

  (* Add <smm> feature if UEFI requires it.  Note that libvirt
   * capabilities doesn't list this feature even if it is supported
   * by qemu, so we have to blindly add it, which might cause libvirt
   * to fail. (XXX)
   *)
  let features = if smm then StringSet.add "smm" features else features in

  let features = List.sort compare (StringSet.elements features) in

  append body [
    e "features" [] (List.map (fun s -> e s [] []) features);
  ];

  (* The <os> section subelements. *)
  let os_section =
    let machine = if machine_q35 then [ "machine", "q35" ] else [] in

    let loader =
      match uefi_firmware with
      | None -> []
      | Some { Uefi.code = code; vars = vars_template } ->
         let secure =
           if secure_boot_required then [ "secure", "yes" ] else [] in
         [ e "loader" (["readonly", "yes"; "type", "pflash"] @ secure)
             [ PCData code ];
           e "nvram" ["template", vars_template] [] ] in

    (e "type" (["arch", guestcaps.gcaps_arch] @ machine) [PCData "hvm"])
    :: loader in

  append body [
    e "os" [] os_section;

    e "on_poweroff" [] [PCData "destroy"];
    e "on_reboot" [] [PCData "restart"];
    e "on_crash" [] [PCData "restart"];
  ];

  (* The devices. *)
  let devices = ref [] in

  (* Fixed and removable disks. *)
  let disks =
    let make_disk bus_name drive_prefix i = function
    | BusSlotEmpty -> Comment (sprintf "%s slot %d is empty" bus_name i)

    | BusSlotTarget t ->
        e "disk" [
          "type", if pool = None then "file" else "volume";
          "device", "disk"
        ] [
          e "driver" [
            "name", "qemu";
            "type", t.target_format;
            "cache", "none"
          ] [];
          (match pool with
          | None ->
            e "source" [
              "file", absolute_path t.target_file;
            ] []
          | Some pool ->
            e "source" [
              "pool", pool;
              "volume", Filename.basename t.target_file;
            ] []
          );
          e "target" [
            "dev", drive_prefix ^ drive_name i;
            "bus", bus_name;
          ] [];
        ]

    | BusSlotRemovable { s_removable_type = CDROM } ->
        e "disk" [ "device", "cdrom"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [
            "dev", drive_prefix ^ drive_name i;
            "bus", bus_name
          ] []
        ]

    | BusSlotRemovable { s_removable_type = Floppy } ->
        e "disk" [ "device", "floppy"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [
            "dev", drive_prefix ^ drive_name i;
          ] []
        ]
    in

    List.flatten [
      Array.to_list
        (Array.mapi (make_disk "virtio" "vd")
                    target_buses.target_virtio_blk_bus);
      Array.to_list
        (Array.mapi (make_disk "ide" "hd")
                    target_buses.target_ide_bus);
      Array.to_list
        (Array.mapi (make_disk "scsi" "sd")
                    target_buses.target_scsi_bus);
      Array.to_list
        (Array.mapi (make_disk "floppy" "fd")
                    target_buses.target_floppy_bus)
    ] in
  append devices disks;

  let nics =
    let net_model =
      match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio" | E1000 -> "e1000" | RTL8139 -> "rtl8139" in
    List.map (
      fun { s_mac = mac; s_vnet_type = vnet_type;
            s_vnet = vnet; s_vnet_orig = vnet_orig } ->
        let vnet_type_str =
          match vnet_type with
          | Bridge -> "bridge" | Network -> "network" in

        let nic =
          let children = [
            e "source" [ vnet_type_str, vnet ] [];
            e "model" [ "type", net_model ] [];
          ] in
          let children =
            if vnet_orig <> vnet then
              Comment (sprintf "%s mapped from \"%s\" to \"%s\""
                         vnet_type_str vnet_orig vnet) :: children
            else
              children in
          e "interface" [ "type", vnet_type_str ] children in

        (match mac with
        | None -> ()
        | Some mac ->
          append_child (e "mac" [ "address", mac ] []) nic);

        nic
    ) source.s_nics in
  append devices nics;

  (* Same as old virt-v2v, we always add a display here even if it was
   * missing from the old metadata.
   *)
  let video =
    let video_model =
      match guestcaps.gcaps_video with
      | QXL ->    e "model" [ "type", "qxl"; "ram", "65536" ] []
      | Cirrus -> e "model" [ "type", "cirrus"; "vram", "9216" ] [] in
    append_attr ("heads", "1") video_model;
    e "video" [] [ video_model ] in
  push_back devices video;

  let graphics =
    match source.s_display with
    | None -> e "graphics" [ "type", "vnc" ] []
    | Some { s_display_type = Window } ->
       e "graphics" [ "type", "sdl" ] []
    | Some { s_display_type = VNC } ->
       e "graphics" [ "type", "vnc" ] []
    | Some { s_display_type = Spice } ->
       e "graphics" [ "type", "spice" ] [] in

  (match source.s_display with
   | Some { s_keymap = Some km } -> append_attr ("keymap", km) graphics
   | Some { s_keymap = None } | None -> ());
  (match source.s_display with
   | Some { s_password = Some pw } -> append_attr ("passwd", pw) graphics
   | Some { s_password = None } | None -> ());
  (match source.s_display with
   | Some { s_listen = listen } ->
      (match listen with
       | LNoListen -> ()
       | LAddress a ->
          let sub = e "listen" [ "type", "address"; "address", a ] [] in
          append_child sub graphics
       | LNetwork n ->
          let sub = e "listen" [ "type", "network"; "network", n ] [] in
          append_child sub graphics
       | LSocket s ->
          let attrs = [ "type", "socket" ] @
            match s with None -> [] | Some s -> [ "socket", s ] in
          let sub = e "listen" attrs [] in
          append_child sub graphics
       | LNone ->
          let sub = e "listen" [ "type", "none" ] [] in
          append_child sub graphics
      )
   | None -> ());
  (match source.s_display with
   | Some { s_port = Some p } ->
      append_attr ("autoport", "no") graphics;
      append_attr ("port", string_of_int p) graphics
   | Some { s_port = None } | None ->
      append_attr ("autoport", "yes") graphics;
      append_attr ("port", "-1") graphics);
  push_back devices graphics;

  let sound =
    match source.s_sound with
    | None -> []
    | Some { s_sound_model = model } ->
       if qemu_supports_sound_card model then
         [ e "sound" [ "model", string_of_source_sound_model model ] [] ]
       else
         [] in
  append devices sound;

  (* Miscellaneous KVM devices. *)
  if guestcaps.gcaps_virtio_rng then
    push_back devices (
      e "rng" ["model", "virtio"] [
        (* XXX Using /dev/urandom requires libvirt >= 1.3.4.  Libvirt
         * was broken before that.
         *)
        e "backend" ["model", "random"] [PCData "/dev/urandom"]
      ]
    );
  (* For the balloon device, libvirt adds an implicit device
   * unless we use model='none', hence this:
   *)
  push_back devices (
    e "memballoon"
      ["model",
       if guestcaps.gcaps_virtio_balloon then "virtio" else "none"]
      []
  );
  if guestcaps.gcaps_isa_pvpanic then
    push_back devices (
      e "panic" ["model", "isa"] [
        e "address" ["type", "isa"; "iobase", "0x505"] []
      ]
    );

  (* Standard devices added to every guest. *)
  append devices [
    e "input" ["type", "tablet"; "bus", "usb"] [];
    e "input" ["type", "mouse"; "bus", "ps2"] [];
    e "console" ["type", "pty"] [];
  ];

  append body [
    e "devices" [] !devices;
  ];

  let doc : doc =
    doc "domain" [
      "type", "kvm";                (* Always assume target is kvm? *)
    ] !body in

  doc
