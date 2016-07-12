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

let rec install_drivers g inspect systemroot root current_cs =
  (* Copy the virtio drivers to the guest. *)
  let driverdir = sprintf "%s/Drivers/VirtIO" systemroot in
  g#mkdir_p driverdir;

  if not (copy_drivers g inspect driverdir) then (
    warning (f_"there are no virtio drivers available for this version of Windows (%d.%d %s %s).  virt-v2v looks for drivers in %s\n\nThe guest will be configured to use slower emulated devices.")
            inspect.i_major_version inspect.i_minor_version inspect.i_arch
            inspect.i_product_variant virtio_win;
    ( IDE, RTL8139, Cirrus )
  )
  else (
    (* Can we install the block driver? *)
    let block : guestcaps_block_type =
      let source = driverdir // "viostor.sys" in
      if g#exists source then (
        let target = sprintf "%s/system32/drivers/viostor.sys" systemroot in
        let target = g#case_sensitive_path target in
        g#cp source target;
        add_viostor_to_registry g inspect root current_cs;
        Virtio_blk
      ) else (
        warning (f_"there is no viostor (virtio block device) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        IDE
      ) in

    (* Can we install the virtio-net driver? *)
    let net : guestcaps_net_type =
      if not (g#exists (driverdir // "netkvm.inf")) then (
        warning (f_"there is no virtio network driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        RTL8139
      )
      else
        (* It will be installed at firstboot. *)
        Virtio_net in

    (* Can we install the QXL driver? *)
    let video : guestcaps_video_type =
      if not (g#exists (driverdir // "qxl.inf")) then (
        warning (f_"there is no QXL driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a basic VGA display driver.")
                inspect.i_major_version inspect.i_minor_version
                inspect.i_arch virtio_win;
        Cirrus
      )
      else
        (* It will be installed at firstboot. *)
        QXL in

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
      [ current_cs; "Control"; "CriticalDeviceDatabase"; "pci#ven_1af4&dev_1001&subsys_00000000" ],
      [ "Service", REG_SZ "viostor";
        "ClassGUID", REG_SZ "{4D36E97B-E325-11CE-BFC1-08002BE10318}" ];

      [ current_cs; "Control"; "CriticalDeviceDatabase"; "pci#ven_1af4&dev_1001&subsys_00020000" ],
      [ "Service", REG_SZ "viostor";
        "ClassGUID", REG_SZ "{4D36E97B-E325-11CE-BFC1-08002BE10318}" ];

      [ current_cs; "Control"; "CriticalDeviceDatabase"; "pci#ven_1af4&dev_1001&subsys_00021af4" ],
      [ "Service", REG_SZ "viostor";
        "ClassGUID", REG_SZ "{4D36E97B-E325-11CE-BFC1-08002BE10318}" ];

      [ current_cs; "Control"; "CriticalDeviceDatabase"; "pci#ven_1af4&dev_1001&subsys_00021af4&rev_00" ],
      [ "Service", REG_SZ "viostor";
        "ClassGUID", REG_SZ "{4D36E97B-E325-11CE-BFC1-08002BE10318}" ];

      [ current_cs; "Services"; "viostor" ],
      [ "Type", REG_DWORD 0x1_l;
        "Start", REG_DWORD 0x0_l;
        "Group", REG_SZ "SCSI miniport";
        "ErrorControl", REG_DWORD 0x1_l;
        "ImagePath", REG_EXPAND_SZ "system32\\drivers\\viostor.sys";
        "Tag", REG_DWORD 0x21_l ];

      [ current_cs; "Services"; "viostor"; "Parameters" ],
      [ "BusType", REG_DWORD 0x1_l ];

      [ current_cs; "Services"; "viostor"; "Parameters"; "MaxTransferSize" ],
      [ "ParamDesc", REG_SZ "Maximum Transfer Size";
        "type", REG_SZ "enum";
        "default", REG_SZ "0" ];

      [ current_cs; "Services"; "viostor"; "Parameters"; "MaxTransferSize"; "enum" ],
      [ "0", REG_SZ "64  KB";
        "1", REG_SZ "128 KB";
        "2", REG_SZ "256 KB" ];

      [ current_cs; "Services"; "viostor"; "Parameters"; "PnpInterface" ],
      [ "5", REG_DWORD 0x1_l ];

      [ current_cs; "Services"; "viostor"; "Enum" ],
      [ "0", REG_SZ "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00\\3&13c0b0c5&0&20";
        "Count", REG_DWORD 0x1_l;
        "NextInstance", REG_DWORD 0x1_l ];
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
       (* Create the key. *)
       g#hivex_node_set_value node oem_inf (* REG_NONE *) 0_L "";
       oem_inf in

  (* There should be a key
   *   HKLM\SYSTEM\ControlSet001\Control\Class\<scsi_adapter_guid>
   * There may be subkey(s) of this called "0000", "0001" etc.  We want
   * to create the next free subkey.  MSFT covers the key here:
   *   https://technet.microsoft.com/en-us/library/cc957341.aspx
   * That page incorrectly states that the key has the form "000n".
   * In fact we observed from real registries that the key is a
   * decimal number that goes 0009 -> 0010 etc.
   *)
  let controller_path =
    [ current_cs; "Control"; "Class"; scsi_adapter_guid ] in
  let controller_offset = get_controller_offset g root controller_path in

  let regedits = [
      controller_path @ [ controller_offset ],
      [ "DriverDate", REG_SZ "6-4-2014";
        "DriverDateData", REG_BINARY "\x00\x40\x90\xed\x87\x7f\xcf\x01";
        "DriverDesc", REG_SZ "Red Hat VirtIO SCSI controller";
        "DriverVersion", REG_SZ "62.71.104.8600" (* XXX *);
        "InfPath", REG_SZ oem_inf;
        "InfSection", REG_SZ "rhelscsi_inst";
        "MatchingDeviceId", REG_SZ "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00";
        "ProviderName", REG_SZ "Red Hat, Inc." ];

      [ current_cs; "Enum"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00\\3&13c0b0c5&0&38" ],
      [ "Capabilities", REG_DWORD 0x6_l;
        "ClassGUID", REG_SZ scsi_adapter_guid;
        "CompatibleIDs", REG_MULTI_SZ [
                             "PCI\\VEN_1AF4&DEV_1001&REV_00";
                             "PCI\\VEN_1AF4&DEV_1001";
                             "PCI\\VEN_1AF4&CC_010000";
                             "PCI\\VEN_1AF4&CC_0100";
                             "PCI\\VEN_1AF4";
                             "PCI\\CC_010000";
                             "PCI\\CC_0100";
                           ];
        "ConfigFlags", REG_DWORD 0_l;
        "ContainerID", REG_SZ "{00000000-0000-0000-ffff-ffffffffffff}";
        "DeviceDesc", REG_SZ (sprintf "@%s,%%rhelscsi.devicedesc%%;Red Hat VirtIO SCSI controller" oem_inf);
        "Driver", REG_SZ (sprintf "%s\\%s" scsi_adapter_guid controller_offset);
        "HardwareID", REG_MULTI_SZ [
                          "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00";
                          "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4";
                          "PCI\\VEN_1AF4&DEV_1001&CC_010000";
                          "PCI\\VEN_1AF4&DEV_1001&CC_0100";
                        ];
        "LocationInformation", REG_SZ "@System32\\drivers\\pci.sys,#65536;PCI bus %1, device %2, function %3;(0,7,0)";
        "Mfg", REG_SZ (sprintf "@%s,%%rhel%%;Red Hat, Inc." oem_inf);
        "ParentIdPrefix", REG_SZ "4&87f7bfb&0";
        "Service", REG_SZ "viostor";
        "UINumber", REG_DWORD 0x7_l ];

      [ current_cs; "Services"; "viostor" ],
      [ "ErrorControl", REG_DWORD 0x1_l;
        "Group", REG_SZ "SCSI miniport";
        "ImagePath", REG_EXPAND_SZ "system32\\drivers\\viostor.sys";
        "Owners", REG_MULTI_SZ [ oem_inf ];
        "Start", REG_DWORD 0x0_l;
        "Tag", REG_DWORD 0x58_l;
        "Type", REG_DWORD 0x1_l ];

      [ current_cs; "Services"; "viostor"; "Parameters" ],
      [ "BusType", REG_DWORD 0x1_l ];

      [ current_cs; "Services"; "viostor"; "Parameters"; "PnpInterface" ],
      [ "5", REG_DWORD 0x1_l ];

      [ "DriverDatabase"; "DriverInfFiles"; oem_inf ],
      [ "", REG_MULTI_SZ [ viostor_inf ];
        "Active", REG_SZ viostor_inf;
        "Configurations", REG_MULTI_SZ [ "rhelscsi_inst" ]
      ];

      [ "DriverDatabase"; "DeviceIds"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00" ],
      [ oem_inf, REG_BINARY "\x01\xff\x00\x00" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf ],
      [ "", REG_SZ oem_inf;
        "F6", REG_DWORD 0x1_l;
        "InfName", REG_SZ "viostor.inf";
        "OemPath", REG_SZ ("X:\\windows\\System32\\DriverStore\\FileRepository\\" ^ viostor_inf);
        "Provider", REG_SZ "Red Hat, Inc.";
        "SignerName", REG_SZ "Microsoft Windows Hardware Compatibility Publisher";
        "SignerScore", REG_DWORD 0x0d000005_l;
        "StatusFlags", REG_DWORD 0x00000012_l;
        (* NB: scsi_adapter_guid appears inside this string. *)
        "Version", REG_BINARY "\x00\xff\x09\x00\x00\x00\x00\x00\x7b\xe9\x36\x4d\x25\xe3\xce\x11\xbf\xc1\x08\x00\x2b\xe1\x03\x18\x00\x40\x90\xed\x87\x7f\xcf\x01\x98\x21\x68\x00\x47\x00\x3e\x00\x00\x00\x00\x00\x00\x00\x00\x00" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst" ],
      [ "ConfigFlags", REG_DWORD 0_l;
        "Service", REG_SZ "viostor" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Device" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Device"; "Interrupt Management" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Device"; "Interrupt Management"; "Affinity Policy" ],
      [ "DevicePolicy", REG_DWORD 0x00000005_l ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Device"; "Interrupt Management"; "MessageSignaledInterruptProperties" ],
      [ "MSISupported", REG_DWORD 0x00000001_l;
        "MessageNumberLimit", REG_DWORD 0x00000002_l ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Services" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Services"; "viostor" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Services"; "viostor"; "Parameters" ],
      [ "BusType", REG_DWORD 0x00000001_l ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Configurations"; "rhelscsi_inst"; "Services"; "viostor"; "Parameters"; "PnpInterface" ],
      [ "5", REG_DWORD 0x00000001_l ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Descriptors" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Descriptors"; "PCI" ],
      [];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Descriptors"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00" ],
      [ "Configuration", REG_SZ "rhelscsi_inst";
        "Description", REG_SZ "%rhelscsi.devicedesc%";
        "Manufacturer", REG_SZ "%rhel%" ];

      [ "DriverDatabase"; "DriverPackages"; viostor_inf; "Strings" ],
      [ "rhel", REG_SZ "Red Hat, Inc.";
        "rhelscsi.devicedesc", REG_SZ "Red Hat VirtIO SCSI controller" ];
    ] in

  reg_import g root regedits;

(*
       A few more keys which we don't add above.  Note that "oem1.inf" ==
       6f,00,65,00,6d,00,31,00,2e,00,69,00,6e,00,66,00.

       [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\PCI\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00\3&13c0b0c5&0&38\Properties\{540b947e-8b40-45bc-a8a2-6a0b894cbda2}\0007]
       @=hex(ffff0012):6f,00,65,00,6d,00,31,00,2e,00,69,00,6e,00,66,00,3a,00,50,00,43,00,49,00,5c,00,56,00,45,00,4e,00,5f,00,31,00,41,00,46,00,34,00,26,00,44,00,45,00,56,00,5f,00,31,00,30,00,30,00,31,00,26,00,53,00,55,00,42,00,53,00,59,00,53,00,5f,00,30,00,30,00,30,00,32,00,31,00,41,00,46,00,34,00,26,00,52,00,45,00,56,00,5f,00,30,00,30,00,2c,00,72,00,68,00,65,00,6c,00,73,00,63,00,73,00,69,00,5f,00,69,00,6e,00,73,00,74,00,00,00

       [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\PCI\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00\3&13c0b0c5&0&38\Properties\{83da6326-97a6-4088-9453-a1923f573b29}\0003]
       @=hex(ffff0012):6f,00,65,00,6d,00,31,00,2e,00,69,00,6e,00,66,00,3a,00,32,00,65,00,35,00,31,00,37,00,32,00,63,00,33,00,62,00,33,00,37,00,62,00,65,00,39,00,39,00,38,00,3a,00,72,00,68,00,65,00,6c,00,73,00,63,00,73,00,69,00,5f,00,69,00,6e,00,73,00,74,00,3a,00,36,00,32,00,2e,00,37,00,31,00,2e,00,31,00,30,00,34,00,2e,00,38,00,36,00,30,00,30,00,3a,00,50,00,43,00,49,00,5c,00,56,00,45,00,4e,00,5f,00,31,00,41,00,46,00,34,00,26,00,44,00,45,00,56,00,5f,00,31,00,30,00,30,00,31,00,26,00,53,00,55,00,42,00,53,00,59,00,53,00,5f,00,30,00,30,00,30,00,32,00,31,00,41,00,46,00,34,00,26,00,52,00,45,00,56,00,5f,00,30,00,30,00,00,00

       [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\PCI\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00\3&13c0b0c5&0&38\Properties\{a8b865dd-2e3d-4094-ad97-e593a70c75d6}\0005]
       @=hex(ffff0012):6f,00,65,00,6d,00,31,00,2e,00,69,00,6e,00,66,00,00,00
*)

and get_controller_offset g root controller_path =
  match Windows.get_node g root controller_path with
  | None ->
     error (f_"cannot find HKLM\\SYSTEM\\%s in the guest registry")
           (String.concat "\\" controller_path)
  | Some node ->
     let rec loop node i =
       let controller_offset = sprintf "%04d" i in
       let child = g#hivex_node_get_child node controller_offset in
       if child = 0_L then controller_offset else loop node (i+1)
     in
     loop node 0

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
