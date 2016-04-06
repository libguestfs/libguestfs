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

open Regedit

open Types
open Utils

let virtio_win =
  try Sys.getenv "VIRTIO_WIN"
  with Not_found ->
    try Sys.getenv "VIRTIO_WIN_DIR" (* old name for VIRTIO_WIN *)
    with Not_found ->
      Guestfs_config.datadir // "virtio-win"

let rec install_drivers g inspect systemroot root current_cs rcaps =
  (* Copy the virtio drivers to the guest. *)
  let driverdir = sprintf "%s/Drivers/VirtIO" systemroot in
  g#mkdir_p driverdir;

  if not (copy_drivers g inspect driverdir) then (
    match rcaps with
    | { rcaps_block_bus = Some Virtio_blk }
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
      (IDE, net_type, Cirrus)
  )
  else (
    (* Can we install the block driver? *)
    let block : guestcaps_block_type =
      let has_viostor = g#exists (driverdir // "viostor.inf") in
      match rcaps.rcaps_block_bus, has_viostor with
      | Some Virtio_blk, false ->
        error (f_"there is no viostor (virtio block device) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
              inspect.i_major_version inspect.i_minor_version
              inspect.i_arch virtio_win

      | None, false ->
        warning (f_"there is no viostor (virtio block device) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        IDE

      | (Some Virtio_blk | None), true ->
        (* Block driver needs tweaks to allow booting; the rest is set up by PnP
         * manager *)
        let source = driverdir // "viostor.sys" in
        let target = sprintf "%s/system32/drivers/viostor.sys" systemroot in
        let target = g#case_sensitive_path target in
        g#cp source target;
        add_viostor_to_registry g inspect root current_cs;
        Virtio_blk

      | Some IDE, _ ->
        IDE in

    (* Can we install the virtio-net driver? *)
    let net : guestcaps_net_type =
      let has_netkvm = g#exists (driverdir // "netkvm.inf") in
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

    (block, net, video)
  )

and add_viostor_to_registry g inspect root current_cs =
  let { i_major_version = major; i_minor_version = minor;
        i_arch = arch } = inspect in
  if (major == 6 && minor >= 2) || major >= 7 then (* Windows >= 8 *)
    add_viostor_to_driver_database g root arch current_cs
  else                          (* Windows <= 7 *)
    add_viostor_to_critical_device_database g root current_cs

and add_viostor_to_critical_device_database g root current_cs =
  (* See http://rwmj.wordpress.com/2010/04/30/tip-install-a-device-driver-in-a-windows-vm/
   * NB: All these edits are in the HKLM\SYSTEM hive.  No other
   * hive may be modified here.
   *)
  let regedits = [
      [ current_cs; "Control"; "CriticalDeviceDatabase"; "pci#ven_1af4&dev_1001&subsys_00021af4&rev_00" ],
      [ "Service", REG_SZ "viostor";
        "ClassGUID", REG_SZ "{4D36E97B-E325-11CE-BFC1-08002BE10318}" ];

      [ current_cs; "Services"; "viostor" ],
      [ "Type", REG_DWORD 0x1_l;
        "Start", REG_DWORD 0x0_l;
        "Group", REG_SZ "SCSI miniport";
        "ErrorControl", REG_DWORD 0x1_l;
        "ImagePath", REG_EXPAND_SZ "system32\\drivers\\viostor.sys" ];
    ] in

  reg_import g root regedits

and add_viostor_to_driver_database g root arch current_cs =
  (* Windows >= 8 doesn't use the CriticalDeviceDatabase.  Instead
   * one must add keys into the DriverDatabase.
   *)

  let viostor_inf =
    let arch =
      match arch with
      | "x86_64" -> "amd64"
      | "i386" | "i486" | "i585" | "i686" -> "x86"
      | _ ->
         error (f_"when adding viostor to the DriverDatabase, unknown architecture: %s") arch in
    (* XXX I don't know what the significance of the c863.. string is.  It
     * may even be random.
     *)
    sprintf "viostor.inf_%s_%s" arch "c86329aaeb0a7904" in

  let scsi_adapter_guid = "{4d36e97b-e325-11ce-bfc1-08002be10318}" in
  (* There should be a key
   *   HKLM\SYSTEM\DriverDatabase\DeviceIds\<scsi_adapter_guid>
   * We want to add:
   *   "oem1.inf"=hex(0):
   * but if we find "oem1.inf" we'll add "oem2.inf" (etc).
   *)
  let oem_inf =
    let path = [ "DriverDatabase"; "DeviceIds"; scsi_adapter_guid ] in
    match Windows.get_node g root path with
    | None ->
       error (f_"cannot find HKLM\\SYSTEM\\DriverDatabase\\DeviceIds\\%s in the guest registry") scsi_adapter_guid
    | Some node ->
       let rec loop node i =
         let oem_inf = sprintf "oem%d.inf" i in
         let value = g#hivex_node_get_value node oem_inf in
         if value = 0_L then oem_inf else loop node (i+1)
       in
       let oem_inf = loop node 1 in
       oem_inf in

  let regedits = [
      [ current_cs; "Services"; "viostor" ],
      [ "ErrorControl", REG_DWORD 0x1_l;
        "Group", REG_SZ "SCSI miniport";
        "ImagePath", REG_EXPAND_SZ "system32\\drivers\\viostor.sys";
        "Start", REG_DWORD 0x0_l;
        "Type", REG_DWORD 0x1_l ];

      [ "DriverDatabase"; "DriverInfFiles"; oem_inf ],
      [ "", REG_MULTI_SZ [ viostor_inf ];
        "Active", REG_SZ viostor_inf;
        "Configurations", REG_MULTI_SZ [ "rhelscsi_inst" ]
      ];

      [ "DriverDatabase"; "DeviceIds"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00" ],
      [ oem_inf, REG_BINARY "\x01\xff\x00\x00" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst" ],
      [ "ConfigFlags", REG_DWORD 0_l;
        "Service", REG_SZ "viostor" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Descriptors"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00" ],
      [ "Configuration", REG_SZ "rhelscsi_inst" ]
    ] in

  reg_import g root regedits

(* Copy the matching drivers to the driverdir; return true if any have
 * been copied.
 *)
and copy_drivers g inspect driverdir =
  let ret = ref false in
  if is_directory virtio_win then (
    let cmd = sprintf "cd %s && find -type f" (quote virtio_win) in
    let paths = external_command cmd in
    List.iter (
      fun path ->
        if virtio_iso_path_matches_guest_os path inspect then (
          let source = virtio_win // path in
          let target = driverdir //
                         String.lowercase_ascii (Filename.basename path) in
          if verbose () then
            printf "Copying virtio driver bits: 'host:%s' -> '%s'\n"
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
            if verbose () then
              printf "Copying virtio driver bits: '%s:%s' -> '%s'\n"
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
    let lc_basename = Filename.basename lc_path in

    let extension =
      match last_part_of lc_basename '.' with
      | Some x -> x
      | None -> raise Not_found
    in

    (* Skip files without specific extensions. *)
    let extensions = ["cat"; "inf"; "pdb"; "sys"] in
    if not (List.mem extension extensions) then raise Not_found;

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
      else
        raise Not_found in

    arch = p_arch && os_major = p_os_major && os_minor = p_os_minor &&
      match_os_variant os_variant

  with Not_found -> false

(* The following function is only exported for unit tests. *)
module UNIT_TESTS = struct
  let virtio_iso_path_matches_guest_os = virtio_iso_path_matches_guest_os
end
