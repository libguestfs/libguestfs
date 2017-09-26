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
open Tools_utils
open Common_gettext.Gettext

open Regedit

open Types
open Utils

let virtio_win =
  try Sys.getenv "VIRTIO_WIN"
  with Not_found ->
    try Sys.getenv "VIRTIO_WIN_DIR" (* old name for VIRTIO_WIN *)
    with Not_found ->
      let iso = Guestfs_config.datadir // "virtio-win" // "virtio-win.iso" in
      if Sys.file_exists iso then iso
      else Guestfs_config.datadir // "virtio-win"

let scsi_class_guid = "{4D36E97B-E325-11CE-BFC1-08002BE10318}"
let viostor_legacy_pciid = "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00"
let viostor_modern_pciid = "VEN_1AF4&DEV_1042&SUBSYS_11001AF4&REV_01"
let vioscsi_legacy_pciid = "VEN_1AF4&DEV_1004&SUBSYS_00081AF4&REV_00"
let vioscsi_modern_pciid = "VEN_1AF4&DEV_1048&SUBSYS_11001AF4&REV_01"

let rec install_drivers ((g, _) as reg) inspect rcaps =
  (* Copy the virtio drivers to the guest. *)
  let driverdir = sprintf "%s/Drivers/VirtIO" inspect.i_windows_systemroot in
  g#mkdir_p driverdir;

  if not (copy_drivers g inspect driverdir) then (
    match rcaps with
    | { rcaps_block_bus = Some Virtio_blk | Some Virtio_SCSI }
    | { rcaps_net_bus = Some Virtio_net }
    | { rcaps_video = Some QXL } ->
      error (f_"there are no virtio drivers available for this version of Windows (%d.%d %s %s).  virt-v2v looks for drivers in %s")
            inspect.i_major_version inspect.i_minor_version inspect.i_arch
            inspect.i_product_variant virtio_win

    | { rcaps_block_bus = (Some IDE | None);
        rcaps_net_bus = ((Some E1000 | Some RTL8139 | None) as net_type);
        rcaps_video = (Some Cirrus | None) } ->
      warning (f_"there are no virtio drivers available for this version of Windows (%d.%d %s %s).  virt-v2v looks for drivers in %s\n\nThe guest will be configured to use slower emulated devices.")
              inspect.i_major_version inspect.i_minor_version inspect.i_arch
              inspect.i_product_variant virtio_win;
      let net_type =
        match net_type with
        | Some model -> model
        | None -> RTL8139 in
      (IDE, net_type, Cirrus, false, false, false)
  )
  else (
    (* Can we install the block driver? *)
    let block : guestcaps_block_type =
      let filenames = ["virtio_blk"; "vrtioblk"; "viostor"] in
      let viostor_driver = try (
        Some (
          List.find (
            fun driver_file ->
              let source = driverdir // driver_file ^ ".sys" in
              g#exists source
          ) filenames
        )
      ) with Not_found -> None in
      let has_vioscsi = g#exists (driverdir // "vioscsi.inf") in
      match rcaps.rcaps_block_bus, viostor_driver, has_vioscsi with
      | Some Virtio_blk, None, _ ->
        error (f_"there is no virtio block device driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
              inspect.i_major_version inspect.i_minor_version
              inspect.i_arch virtio_win

      | Some Virtio_SCSI, _, false ->
        error (f_"there is no vioscsi (virtio SCSI) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
              inspect.i_major_version inspect.i_minor_version
              inspect.i_arch virtio_win

      | None, None, _ ->
        warning (f_"there is no virtio block device driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        IDE

      | (Some Virtio_blk | None), Some driver_name, _ ->
        (* Block driver needs tweaks to allow booting; the rest is set up by PnP
         * manager *)
        let source = driverdir // (driver_name ^ ".sys") in
        let target = sprintf "%s/system32/drivers/%s.sys"
                             inspect.i_windows_systemroot driver_name in
        let target = g#case_sensitive_path target in
        g#cp source target;
        add_guestor_to_registry reg inspect driver_name viostor_legacy_pciid;
        add_guestor_to_registry reg inspect driver_name viostor_modern_pciid;
        Virtio_blk

      | Some Virtio_SCSI, _, true ->
        (* Block driver needs tweaks to allow booting; the rest is set up by PnP
         * manager *)
        let source = driverdir // "vioscsi.sys" in
        let target = sprintf "%s/system32/drivers/vioscsi.sys"
                             inspect.i_windows_systemroot in
        let target = g#case_sensitive_path target in
        g#cp source target;
        add_guestor_to_registry reg inspect "vioscsi" vioscsi_legacy_pciid;
        add_guestor_to_registry reg inspect "vioscsi" vioscsi_modern_pciid;
        Virtio_SCSI

      | Some IDE, _, _ ->
        IDE in

    (* Can we install the virtio-net driver? *)
    let net : guestcaps_net_type =
      let filenames = ["virtio_net.inf"; "netkvm.inf"] in
      let has_netkvm =
        List.exists (
          fun driver_file -> g#exists (driverdir // driver_file)
        ) filenames in
      match rcaps.rcaps_net_bus, has_netkvm with
      | Some Virtio_net, false ->
        error (f_"there is no virtio network driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s")
              inspect.i_major_version inspect.i_minor_version
              inspect.i_arch virtio_win

      | None, false ->
        warning (f_"there is no virtio network driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        RTL8139

      | (Some Virtio_net | None), true ->
        Virtio_net

      | Some net_type, _ ->
        net_type in

    (* Can we install the QXL driver? *)
    let video : guestcaps_video_type =
      let has_qxl = g#exists (driverdir // "qxl.inf") in
      match rcaps.rcaps_video, has_qxl with
      | Some QXL, false ->
        error (f_"there is no QXL driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s")
              inspect.i_major_version inspect.i_minor_version
              inspect.i_arch virtio_win

      | None, false ->
        warning (f_"there is no QXL driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a basic VGA display driver.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        Cirrus

      | (Some QXL | None), true ->
        QXL

      | Some Cirrus, _ ->
        Cirrus in

    (* Did we install the miscellaneous drivers? *)
    let virtio_rng_supported = g#exists (driverdir // "viorng.inf") in
    let virtio_ballon_supported = g#exists (driverdir // "balloon.inf") in
    let isa_pvpanic_supported = g#exists (driverdir // "pvpanic.inf") in

    (block, net, video,
     virtio_rng_supported, virtio_ballon_supported, isa_pvpanic_supported)
  )

and add_guestor_to_registry ((g, root) as reg) inspect drv_name drv_pciid =
  let ddb_node = g#hivex_node_get_child root "DriverDatabase" in

  let regedits =
    if ddb_node = 0L then
      cdb_regedits inspect drv_name drv_pciid
    else
      ddb_regedits inspect drv_name drv_pciid in

  let drv_sys_path = sprintf "system32\\drivers\\%s.sys" drv_name in
  let common_regedits = [
      [ inspect.i_windows_current_control_set; "Services"; drv_name ],
      [ "Type", REG_DWORD 0x1_l;
        "Start", REG_DWORD 0x0_l;
        "Group", REG_SZ "SCSI miniport";
        "ErrorControl", REG_DWORD 0x1_l;
        "ImagePath", REG_EXPAND_SZ drv_sys_path ];
  ] in

  reg_import reg (regedits @ common_regedits)

and cdb_regedits inspect drv_name drv_pciid =
  (* See http://rwmj.wordpress.com/2010/04/30/tip-install-a-device-driver-in-a-windows-vm/
   * NB: All these edits are in the HKLM\SYSTEM hive.  No other
   * hive may be modified here.
   *)
  [
    [ inspect.i_windows_current_control_set;
      "Control"; "CriticalDeviceDatabase";
      "PCI#" ^ drv_pciid ],
    [ "Service", REG_SZ drv_name;
      "ClassGUID", REG_SZ scsi_class_guid ];
  ]

and ddb_regedits inspect drv_name drv_pciid =
  (* Windows >= 8 doesn't use the CriticalDeviceDatabase.  Instead
   * one must add keys into the DriverDatabase.
   *)

  let drv_inf = "guestor.inf" in
  let drv_inf_label = drv_inf ^ "_tmp" in
  let drv_config = "guestor_conf" in

  [
    [ "DriverDatabase"; "DriverInfFiles"; drv_inf ],
    [ "", REG_MULTI_SZ [ drv_inf_label ];
      "Active", REG_SZ drv_inf_label;
      "Configurations", REG_MULTI_SZ [ drv_config ] ];

    [ "DriverDatabase"; "DeviceIds"; "PCI"; drv_pciid ],
    [ drv_inf, REG_BINARY "\x01\xff\x00\x00" ];

    [ "DriverDatabase"; "DriverPackages"; drv_inf_label ],
    [ "Version", REG_BINARY ("\x00\xff\x09\x00\x00\x00\x00\x00" ^
                             "\x7b\xe9\x36\x4d\x25\xe3\xce\x11" ^
                             "\xbf\xc1\x08\x00\x2b\xe1\x03\x18" ^
                             (String.make 24 '\x00')) ];
    (* Version is necessary for Windows-Kernel-Pnp in w10/w2k16 *)

    [ "DriverDatabase"; "DriverPackages"; drv_inf_label;
      "Configurations"; drv_config ],
    [ "ConfigFlags", REG_DWORD 0_l;
      "Service", REG_SZ drv_name ];

    [ "DriverDatabase"; "DriverPackages"; drv_inf_label;
      "Descriptors"; "PCI"; drv_pciid ],
    [ "Configuration", REG_SZ drv_config ];
  ]

(* Copy the matching drivers to the driverdir; return true if any have
 * been copied.
 *)
and copy_drivers g inspect driverdir =
  let ret = ref false in
  if is_directory virtio_win then (
    let cmd = sprintf "cd %s && find -L -type f" (quote virtio_win) in
    let paths = external_command cmd in
    List.iter (
      fun path ->
        if virtio_iso_path_matches_guest_os path inspect then (
          let source = virtio_win // path in
          let target = driverdir //
                         String.lowercase_ascii (Filename.basename path) in
          debug "copying virtio driver bits: 'host:%s' -> '%s'"
                source target;

          g#write target (read_whole_file source);
          ret := true
        )
      ) paths
  )
  else if is_regular_file virtio_win then (
    try
      let g2 = open_guestfs ~identifier:"virtio_win" () in
      g2#add_drive_opts virtio_win ~readonly:true;
      g2#launch ();
      let vio_root = "/" in
      g2#mount_ro "/dev/sda" vio_root;
      let paths = g2#find vio_root in
      Array.iter (
        fun path ->
          let source = vio_root // path in
          if g2#is_file source ~followsymlinks:false &&
               virtio_iso_path_matches_guest_os path inspect then (
            let target = driverdir //
                           String.lowercase_ascii (Filename.basename path) in
            debug "copying virtio driver bits: '%s:%s' -> '%s'"
                  virtio_win path target;

            g#write target (g2#read_file source);
            ret := true
          )
        ) paths;
      g2#close()
    with Guestfs.Error msg ->
      error (f_"%s: cannot open virtio-win ISO file: %s") virtio_win msg
  );
  !ret

(* Given a path of a file relative to the root of the directory tree
 * with virtio-win drivers, figure out if it's suitable for the
 * specific Windows flavor of the current guest.
 *)
and virtio_iso_path_matches_guest_os path inspect =
  let { i_major_version = os_major; i_minor_version = os_minor;
        i_arch = arch; i_product_variant = os_variant } = inspect in
  try
    (* Lowercased path, since the ISO may contain upper or lowercase path
     * elements.
     *)
    let lc_path = String.lowercase_ascii path in

    (* Using the full path, work out what version of Windows
     * this driver is for.  Paths can be things like:
     * "NetKVM/2k12R2/amd64/netkvm.sys" or
     * "./drivers/amd64/Win2012R2/netkvm.sys".
     * Note we check lowercase paths.
     *)
    let pathelem elem = String.find lc_path ("/" ^ elem ^ "/") >= 0 in
    let p_arch =
      if pathelem "x86" || pathelem "i386" then "i386"
      else if pathelem "amd64" then "x86_64"
      else raise Not_found in

    let is_client os_variant = os_variant = "Client"
    and not_client os_variant = os_variant <> "Client"
    and any_variant os_variant = true in
    let p_os_major, p_os_minor, match_os_variant =
      if pathelem "xp" || pathelem "winxp" then
        (5, 1, any_variant)
      else if pathelem "2k3" || pathelem "win2003" then
        (5, 2, any_variant)
      else if pathelem "vista" then
        (6, 0, is_client)
      else if pathelem "2k8" || pathelem "win2008" then
        (6, 0, not_client)
      else if pathelem "w7" || pathelem "win7" then
        (6, 1, is_client)
      else if pathelem "2k8r2" || pathelem "win2008r2" then
        (6, 1, not_client)
      else if pathelem "w8" || pathelem "win8" then
        (6, 2, is_client)
      else if pathelem "2k12" || pathelem "win2012" then
        (6, 2, not_client)
      else if pathelem "w8.1" || pathelem "win8.1" then
        (6, 3, is_client)
      else if pathelem "2k12r2" || pathelem "win2012r2" then
        (6, 3, not_client)
      else if pathelem "w10" || pathelem "win10" then
        (10, 0, is_client)
      else if pathelem "2k16" || pathelem "win2016" then
        (10, 0, not_client)
      else
        raise Not_found in

    arch = p_arch && os_major = p_os_major && os_minor = p_os_minor &&
      match_os_variant os_variant

  with Not_found -> false

(* The following function is only exported for unit tests. *)
module UNIT_TESTS = struct
  let virtio_iso_path_matches_guest_os = virtio_iso_path_matches_guest_os
end
