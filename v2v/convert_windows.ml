(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

open Utils
open Types

module G = Guestfs

(* Convert Windows guests.
 *
 * This only does a "pre-conversion", the steps needed to get the
 * Windows guest to boot on KVM.  Unlike the [Convert_linux] module,
 * this is not a full conversion.  Instead it just installs the
 * [viostor] (Windows virtio block) driver, so that the Windows guest
 * will be able to boot on the target.  A [RunOnce] script is also
 * added to the VM which does all the rest of the conversion the first
 * time the Windows VM is booted on KVM.
 *)

type ('a, 'b) maybe = Either of 'a | Or of 'b

(* Antivirus regexps that match on inspect.i_apps.app2_name fields. *)
let av_rex =
  let alternatives = [
    "virus"; (* generic *)
    "Kaspersky"; "McAfee"; "Norton"; "Sophos";
  ] in
  Str.regexp_case_fold (String.concat "\\|" alternatives)

let convert ~keep_serial_console (g : G.guestfs) inspect source =
  (* Get the data directory. *)
  let virt_tools_data_dir =
    try Sys.getenv "VIRT_TOOLS_DATA_DIR"
    with Not_found -> Config.datadir // "virt-tools" in

  let virtio_win =
    try Sys.getenv "VIRTIO_WIN"
    with Not_found ->
      try Sys.getenv "VIRTIO_WIN_DIR" (* old name for VIRTIO_WIN *)
      with Not_found ->
        Config.datadir // "virtio-win" in

  (* Check if RHEV-APT exists.  This is optional. *)
  let rhev_apt_exe = virt_tools_data_dir // "rhev-apt.exe" in
  let rhev_apt_exe =
    try
      let chan = open_in rhev_apt_exe in
      close_in chan;
      Some rhev_apt_exe
    with
      Sys_error msg ->
        warning (f_"'%s' is missing.  Unable to install RHEV-APT (RHEV guest agent).  Original error: %s")
          rhev_apt_exe msg;
        None in

  let systemroot = g#inspect_get_windows_systemroot inspect.i_root in

  (* This is a wrapper that handles opening and closing the hive
   * properly around a function [f].  If [~write] is [true] then the
   * hive is opened for writing and committed at the end if the
   * function returned without error.
   *)
  let rec with_hive name ~write f =
    let filename = sprintf "%s/system32/config/%s" systemroot name in
    let filename = g#case_sensitive_path filename in
    let verbose = verbose () in
    g#hivex_open ~write ~verbose (* ~debug:verbose *) filename;
    let r =
      try
        let root = g#hivex_root () in
        let ret = f root in
        if write then g#hivex_commit None;
        Either ret
      with exn ->
        Or exn in
    g#hivex_close ();
    match r with Either ret -> ret | Or exn -> raise exn

  (* Find the given node in the current hive, relative to the starting
   * point.  Raises [Not_found] if the node is not found.
   *)
  and get_node node = function
    | [] -> node
    | x :: xs ->
      let node = g#hivex_node_get_child node x in
      if node = 0L then raise Not_found;
      get_node node xs
  in

  (*----------------------------------------------------------------------*)
  (* Inspect the Windows guest. *)

  (* Warn if Windows guest appears to be using group policy. *)
  let has_group_policy =
    let check_group_policy root =
      try
        let node =
          get_node root
                   ["Microsoft"; "Windows"; "CurrentVersion"; "Group Policy";
                    "History"] in
        let children = g#hivex_node_children node in
        let children = Array.to_list children in
        let children =
          List.map (fun { G.hivex_node_h = h } -> g#hivex_node_name h)
                   children in
        (* Just assume any children looking like "{<GUID>}" mean that
         * some GPOs were installed.
         *
         * In future we might want to look for nodes which match:
         * History\{<GUID>}\<N> where <N> is a small integer (the order
         * in which policy objects were applied.
         *
         * For an example registry containing GPOs, see RHBZ#1219651.
         * See also: https://support.microsoft.com/en-us/kb/201453
         *)
        let is_gpo_guid name =
          let len = String.length name in
          len > 3 && name.[0] = '{' && isxdigit name.[1] && name.[len-1] = '}'
        in
        List.exists is_gpo_guid children
      with
        Not_found -> false
    in
    with_hive "software" ~write:false check_group_policy in

  (* Warn if Windows guest has AV installed. *)
  let has_antivirus =
    let check_app { G.app2_name = name } =
      try ignore (Str.search_forward av_rex name 0); true
      with Not_found -> false
    in
    List.exists check_app inspect.i_apps in

  (* Open the software hive (readonly) and find the Xen PV uninstaller,
   * if it exists.
   *)
  let xenpv_uninst =
    let xenpvreg = "Red Hat Paravirtualized Xen Drivers for Windows(R)" in

    let find_xenpv_uninst root =
      try
        let node =
          get_node root
                   ["Microsoft"; "Windows"; "CurrentVersion"; "Uninstall";
                    xenpvreg] in
        let uninstkey = "UninstallString" in
        let valueh = g#hivex_node_get_value node uninstkey in
        if valueh = 0L then (
          warning (f_"cannot uninstall Xen PV drivers: registry key 'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\%s' does not contain an '%s' key")
                  xenpvreg uninstkey;
          raise Not_found
        );
        let data = g#hivex_value_value valueh in
        let data = decode_utf16le data in

        (* The uninstall program will be uninst.exe.  This is a wrapper
         * around _uninst.exe which prompts the user.  As we don't want
         * the user to be prompted, we run _uninst.exe explicitly.
         *)
        let len = String.length data in
        let data =
          if len >= 8 &&
               String.lowercase (String.sub data (len-8) 8) = "uninst.exe" then
            (String.sub data 0 (len-8)) ^ "_uninst.exe"
          else
            data in

        Some data
      with
        Not_found -> None
    in
    with_hive "software" ~write:false find_xenpv_uninst in

  (*----------------------------------------------------------------------*)
  (* Perform the conversion of the Windows guest. *)

  let rec configure_firstboot () =
    configure_rhev_apt ();
    unconfigure_xenpv ()

  and configure_rhev_apt () =
    (* Configure RHEV-APT (the RHEV guest agent).  However if it doesn't
     * exist just warn about it and continue.
     *)
    match rhev_apt_exe with
    | None -> ()
    | Some rhev_apt_exe ->
      g#upload rhev_apt_exe "/rhev-apt.exe"; (* XXX *)

      let fb_script = "\
@echo off

echo installing rhev-apt
\"\\rhev-apt.exe\" /S /v /qn

echo starting rhev-apt
net start rhev-apt
" in
      Firstboot.add_firstboot_script g inspect.i_root
        "configure rhev-apt" fb_script

  and unconfigure_xenpv () =
    match xenpv_uninst with
    | None -> () (* nothing to be uninstalled *)
    | Some uninst ->
      let fb_script = sprintf "\
@echo off

echo uninstalling Xen PV driver
\"%s\"
" uninst in
      Firstboot.add_firstboot_script g inspect.i_root
        "uninstall Xen PV" fb_script
  in

  let rec update_system_hive root =
    (* Update the SYSTEM hive.  When this function is called the hive has
     * already been opened as a hivex handle inside guestfs.
     *)
    (* Find the 'Current' ControlSet. *)
    let current_cs =
      let select = g#hivex_node_get_child root "Select" in
      let valueh = g#hivex_node_get_value select "Current" in
      let value = int_of_le32 (g#hivex_value_value valueh) in
      sprintf "ControlSet%03Ld" value in

    if verbose () then printf "current ControlSet is %s\n%!" current_cs;

    disable_services root current_cs;
    disable_autoreboot root current_cs;
    install_virtio_drivers root current_cs

  and disable_services root current_cs =
    (* Disable miscellaneous services. *)
    let services = get_node root [current_cs; "Services"] in

    (* Disable the Processor and Intelppm services
     * http://blogs.msdn.com/b/virtual_pc_guy/archive/2005/10/24/484461.aspx
     *
     * Disable the rhelscsi service (RHBZ#809273).
     *)
    let disable = [ "Processor"; "Intelppm"; "rhelscsi" ] in
    List.iter (
      fun name ->
        let node = g#hivex_node_get_child services name in
        if node <> 0L then (
          (* Delete the node instead of trying to disable it.  RHBZ#737600. *)
          g#hivex_node_delete_child node
        )
    ) disable

  and disable_autoreboot root current_cs =
    (* If the guest reboots after a crash, it's hard to see the original
     * error (eg. the infamous 0x0000007B).  Turn off autoreboot.
     *)
    try
      let crash_control =
        get_node root [current_cs; "Control"; "CrashControl"] in
      g#hivex_node_set_value crash_control "AutoReboot" 4_L (le32_of_int 0_L)
    with
      Not_found -> ()

  and install_virtio_drivers root current_cs =
    (* Copy the virtio drivers to the guest. *)
    let driverdir = sprintf "%s/Drivers/VirtIO" systemroot in
    g#mkdir_p driverdir;

    (* Load the list of drivers available. *)
    let drivers = find_virtio_win_drivers virtio_win in

    (* Filter out only drivers matching the current guest. *)
    let drivers =
      List.filter (
        fun { vwd_os_arch = arch;
              vwd_os_major = os_major; vwd_os_minor = os_minor;
              vwd_os_variant = os_variant } ->
        arch = inspect.i_arch &&
        os_major = inspect.i_major_version &&
        os_minor = inspect.i_minor_version &&
        (match os_variant with
         | Vwd_client -> inspect.i_product_variant = "Client"
         | Vwd_not_client -> inspect.i_product_variant <> "Client"
         | Vwd_any_variant -> true)
      ) drivers in

    if verbose () then (
      printf "virtio-win driver files matching this guest:\n";
      List.iter print_virtio_win_driver_file drivers;
      flush stdout
    );

    match drivers with
    | [] ->
       warning (f_"there are no virtio drivers available for this version of Windows (%d.%d %s %s).  virt-v2v looks for drivers in %s\n\nThe guest will be configured to use slower emulated devices.")
               inspect.i_major_version inspect.i_minor_version
               inspect.i_arch inspect.i_product_variant
               virtio_win;
       ( IDE, RTL8139, Cirrus )

    | drivers ->
       (* Can we install the block driver? *)
       let block : guestcaps_block_type =
         try
           let viostor_sys_file =
             List.find
               (fun { vwd_filename = filename } -> filename = "viostor.sys")
               drivers in
           (* Get the actual file contents of the .sys file. *)
           let content = viostor_sys_file.vwd_get_contents () in
           let target = sprintf "%s/system32/drivers/viostor.sys" systemroot in
           let target = g#case_sensitive_path target in
           g#write target content;
           add_viostor_to_critical_device_database root current_cs;
           Virtio_blk
         with Not_found ->
           warning (f_"there is no viostor (virtio block device) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use a slower emulated device.")
                   inspect.i_major_version inspect.i_minor_version
                   inspect.i_arch virtio_win;
           IDE in

       (* Can we install the virtio-net driver? *)
       let net : guestcaps_net_type =
         if not (List.exists
                   (fun { vwd_filename = filename } -> filename = "netkvm.inf")
                   drivers) then (
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
         if not (List.exists
                   (fun { vwd_filename = filename } -> filename = "qxl.inf")
                   drivers) then (
           warning (f_"there is no QXL driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver in %s\n\nThe guest will be configured to use standard VGA.")
                   inspect.i_major_version inspect.i_minor_version
                   inspect.i_arch virtio_win;
           Cirrus
         )
         else
           (* It will be installed at firstboot. *)
           QXL in

       (* Copy all the drivers to the driverdir.  They will be
        * installed at firstboot.
        *)
       List.iter (
         fun driver ->
           let content = driver.vwd_get_contents () in
           g#write (driverdir // driver.vwd_filename) content
       ) drivers;

       (block, net, video)

  and add_viostor_to_critical_device_database root current_cs =
    let { i_major_version = major; i_minor_version = minor;
          i_arch = arch } = inspect in
    if (major == 6 && minor >= 2) || major >= 7 then (* Windows >= 8 *)
      add_viostor_to_critical_device_database_ddb root arch current_cs
    else                        (* Windows <= 7 *)
      add_viostor_to_critical_device_database_cddb root current_cs

  and add_viostor_to_critical_device_database_cddb root current_cs =
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

  and add_viostor_to_critical_device_database_ddb root arch current_cs =
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
    let oem1_inf = "oem1.inf" in

    (* There should be a key
     * HKLM\SYSTEM\DriverDatabase\DeviceIds\{4d36e97b-e325-11ce-bfc1-08002be10318}.
     * We want to add:
     * "oem1.inf"=hex(0):
     *)
    let () =
      let node =
        try get_node root [ "DriverDatabase"; "DeviceIds"; scsi_adapter_guid ]
        with Not_found ->
          error (f_"cannot find HKLM\\SYSTEM\\DriverDatabase\\DeviceIds\\%s in the guest registry") scsi_adapter_guid in
      g#hivex_node_set_value node oem1_inf (* REG_NONE *) 0_L "" in

    (* There should be a key
     * HKLM\SYSTEM\ControlSet001\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}
     * There may be subkey(s) of this called "0000", "0001" etc.  We want
     * to create the next free subkey.
     *)
    let controller_path =
      [ current_cs; "Control"; "Class"; scsi_adapter_guid ] in
    let controller_offset =
      let node =
        try get_node root controller_path
        with Not_found ->
          error (f_"cannot find HKLM\\SYSTEM\\%s in the guest registry")
                (String.concat "\\" controller_path) in
      let rec loop node i =
        let controller_offset = sprintf "%04d" i in
        let child = g#hivex_node_get_child node controller_offset in
        if child = 0_L then controller_offset else loop node (i+1)
      in
      loop node 0 in

    let regedits = [
        controller_path @ [ controller_offset ],
        [ "DriverDate", REG_SZ "6-4-2014";
          "DriverDateData", REG_BINARY "\x00\x40\x90\xed\x87\x7f\xcf\x01";
          "DriverDesc", REG_SZ "Red Hat VirtIO SCSI controller";
          "DriverVersion", REG_SZ "62.71.104.8600" (* XXX *);
          "InfPath", REG_SZ oem1_inf;
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
                               "PCI\\VEN_010000";
                               "PCI\\VEN_0100";
                             ];
          "ConfigFlags", REG_DWORD 0_l;
          "ContainerID", REG_SZ "{00000000-0000-0000-ffff-ffffffffffff}";
          "DeviceDesc", REG_SZ (sprintf "@%s,%%rhelscsi.devicedesc%%;Red Hat VirtIO SCSI controller" oem1_inf);
          "Driver", REG_SZ (sprintf "%s\\%s" scsi_adapter_guid controller_offset);
          "HardwareID", REG_MULTI_SZ [
                            "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00";
                            "PCI\\VEN_1AF4&DEV_1001&SUBSYS_00021AF4";
                            "PCI\\VEN_1AF4&DEV_1001&CC_010000";
                            "PCI\\VEN_1AF4&DEV_1001&CC_0100";
                          ];
          "LocationInformation", REG_SZ "@System32\\drivers\\pci.sys,#65536;PCI bus %1, device %2, function %3;(0,7,0)";
          "Mfg", REG_SZ (sprintf "@%s,%%rhel%%;Red Hat, Inc." oem1_inf);
          "ParentIdPrefix", REG_SZ "4&87f7bfb&0";
          "Service", REG_SZ "viostor";
          "UINumber", REG_DWORD 0x7_l ];

        [ current_cs; "Services"; "viostor" ],
        [ "ErrorControl", REG_DWORD 0x1_l;
          "Group", REG_SZ "SCSI miniport";
          "ImagePath", REG_EXPAND_SZ "system32\\drivers\\viostor.sys";
          "Owners", REG_MULTI_SZ [ oem1_inf ];
          "Start", REG_DWORD 0x0_l;
          "Tag", REG_DWORD 0x58_l;
          "Type", REG_DWORD 0x1_l ];

        [ current_cs; "Services"; "viostor"; "Parameters" ],
        [ "BusType", REG_DWORD 0x1_l ];

        [ current_cs; "Services"; "viostor"; "Parameters"; "PnpInterface" ],
        [ "5", REG_DWORD 0x1_l ];

        [ "DriverDatabase"; "DriverInfFiles"; oem1_inf ],
        [ "", REG_MULTI_SZ [ viostor_inf ];
          "Active", REG_SZ viostor_inf;
          "Configurations", REG_MULTI_SZ [ "rhelscsi_inst" ]
        ];

        [ "DriverDatabase"; "DeviceIds"; "PCI"; "VEN_1AF4&DEV_1001&SUBSYS_00021AF4&REV_00" ],
        [ oem1_inf, REG_BINARY "\x01\xff\x00\x00" ];

        [ "DriverDatabase"; "DriverPackages"; viostor_inf ],
        [ "", REG_SZ oem1_inf;
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

  and update_software_hive root =
    (* Update the SOFTWARE hive.  When this function is called the
     * hive has already been opened as a hivex handle inside
     * guestfs.
     *)

    (* Find the node \Microsoft\Windows\CurrentVersion.  If the node
     * has a key called DevicePath then append the virtio driver
     * path to this key.
     *)
    try
      let node = get_node root ["Microsoft"; "Windows"; "CurrentVersion"] in
      let append = encode_utf16le ";%SystemRoot%\\Drivers\\VirtIO" in
      let values = Array.to_list (g#hivex_node_values node) in
      let rec loop = function
        | [] -> () (* DevicePath not found -- ignore this case *)
        | { G.hivex_value_h = valueh } :: values ->
          let key = g#hivex_value_key valueh in
          if key <> "DevicePath" then
            loop values
          else (
            let data = g#hivex_value_value valueh in
            let len = String.length data in
            let t = g#hivex_value_type valueh in

            (* Only add the appended path if it doesn't exist already. *)
            if string_find data append = -1 then (
              (* Remove the explicit [\0\0] at the end of the string.
               * This is the UTF-16LE NUL-terminator.
               *)
              let data =
                if len >= 2 && String.sub data (len-2) 2 = "\000\000" then
                  String.sub data 0 (len-2)
                else
                  data in

              (* Append the path and the explicit NUL. *)
              let data = data ^ append ^ "\000\000" in

              g#hivex_node_set_value node key t data
            )
          )
      in
      loop values
    with Not_found ->
      warning (f_"could not find registry key HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion")

  and fix_ntfs_heads () =
    (* NTFS hardcodes the number of heads on the drive which created
       it in the filesystem header. Modern versions of Windows
       sensibly ignore it, but both Windows XP and Windows 2000
       require it to be correct in order to boot from the drive. If it
       isn't you get:

       'A disk read error occurred. Press Ctrl+Alt+Del to restart'

       QEMU has some code in block.c:guess_disk_lchs() which on the face
       of it appears to infer the drive geometry from the MBR if it's
       valid. However, my tests have shown that a Windows XP guest
       hosted on both RHEL 5 and F14 requires the heads field in NTFS to
       be the following, based solely on drive size:

       Range                             Heads
       size < 2114445312                 0x40
       2114445312 <= size < 4228374780   0x80
       4228374780 <= size                0xFF

       I have not tested drive sizes less than 1G, which require fewer
       heads, as this limitation applies only to the boot device and it
       is not possible to install XP on a drive this size.

       The following page has good information on the layout of NTFS in
       Windows XP/2000:

       http://mirror.href.com/thestarman/asm/mbr/NTFSBR.htm

       Technet has this:

       http://technet.microsoft.com/en-us/library/cc781134(WS.10).aspx#w2k3tr_ntfs_how_dhao

       however, as this is specific to Windows 2003 it lists location
       0x1A as unused.
    *)
    let rootpart = inspect.i_root in

    (* Ignore if the rootpart is something like /dev/sda.  RHBZ#1276540. *)
    if not (g#is_whole_device rootpart) then (
      (* Check that the root device contains NTFS magic. *)
      let magic = g#pread_device rootpart 8 3L in
      if magic = "NTFS    " then (
        (* Get the size of the whole disk containing the root partition. *)
        let rootdev = g#part_to_dev rootpart in (* eg. /dev/sda *)
        let size = g#blockdev_getsize64 rootdev in

        let heads =             (* refer to the table above *)
          if size < 2114445312L then 0x40
          else if size < 4228374780L then 0x80
          else 0xff in

        (* Update NTFS's idea of the number of heads.  This is an
         * unsigned 16 bit little-endian integer, offset 0x1a from the
         * beginning of the partition.
         *)
        let bytes = String.create 2 in
        bytes.[0] <- Char.chr heads;
        bytes.[1] <- '\000';
        ignore (g#pwrite_device rootpart bytes 0x1a_L)
      )
    )
  in

  (* Firstboot configuration. *)
  configure_firstboot ();

  (* Open the system hive and update it. *)
  let block_driver, net_driver, video_driver =
    with_hive "system" ~write:true update_system_hive in

  (* Open the software hive and update it. *)
  with_hive "software" ~write:true update_software_hive;

  fix_ntfs_heads ();

  (* Warn if installation of virtio block drivers might conflict with
   * group policy or AV software causing a boot 0x7B error (RHBZ#1260689).
   *)
  let () =
    if block_driver = Virtio_blk then (
      if has_group_policy then
        warning (f_"this guest has Windows Group Policy Objects (GPO) and a new virtio block device driver was installed.  In some circumstances, Group Policy may prevent new drivers from working (resulting in a 7B boot error).  If this happens, try disabling Group Policy before doing the conversion.");
      if has_antivirus then
        warning (f_"this guest has Anti-Virus (AV) software and a new virtio block device driver was installed.  In some circumstances, AV may prevent new drivers from working (resulting in a 7B boot error).  If this happens, try disabling AV before doing the conversion.");
    ) in

  (* Return guest capabilities. *)
  let guestcaps = {
    gcaps_block_bus = block_driver;
    gcaps_net_bus = net_driver;
    gcaps_video = video_driver;
    gcaps_arch = Utils.kvm_arch inspect.i_arch;
    gcaps_acpi = true;
  } in

  guestcaps

let () =
  let matching = function
    | { i_type = "windows" } -> true
    | _ -> false
  in
  Modules_list.register_convert_module matching "windows" convert
