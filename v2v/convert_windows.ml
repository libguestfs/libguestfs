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

let convert ~verbose ~keep_serial_console (g : G.guestfs) inspect source =
  (* Get the data directory. *)
  let virt_tools_data_dir =
    try Sys.getenv "VIRT_TOOLS_DATA_DIR"
    with Not_found -> Config.datadir // "virt-tools" in

  let virtio_win_dir =
    try Sys.getenv "VIRTIO_WIN_DIR"
    with Not_found -> Config.datadir // "virtio-win" in

  (* Check if RHEV-APT exists.  This is optional. *)
  let rhev_apt_exe = virt_tools_data_dir // "rhev-apt.exe" in
  let rhev_apt_exe =
    try
      let chan = open_in rhev_apt_exe in
      close_in chan;
      Some rhev_apt_exe
    with
      Sys_error msg ->
        warning ~prog (f_"'%s' is missing.  Unable to install RHEV-APT (RHEV guest agent).  Original error: %s")
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

  let find_xenpv_uninst root =
    try
      let xenpvreg = "Red Hat Paravirtualized Xen Drivers for Windows(R)" in
      let node =
        get_node root
          ["Microsoft"; "Windows"; "CurrentVersion"; "Uninstall"; xenpvreg] in
      let uninstkey = "UninstallString" in
      let valueh = g#hivex_node_get_value node uninstkey in
      if valueh = 0L then (
        warning ~prog (f_"cannot uninstall Xen PV drivers: registry key 'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\%s' does not contain an '%s' key")
          xenpvreg uninstkey;
        raise Not_found
      );
      let data = g#hivex_value_value valueh in
      let data = decode_utf16le ~prog data in

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

  (* Open the software hive (readonly) and find the Xen PV uninstaller,
   * if it exists.
   *)
  let xenpv_uninst = with_hive "software" ~write:false find_xenpv_uninst in

  (*----------------------------------------------------------------------*)
  (* Perform the conversion of the Windows guest. *)

  let rec configure_firstboot () =
    let fb = Buffer.create 1024 in
    bprintf fb "@echo off\n";

    configure_rhev_apt fb;
    unconfigure_xenpv fb;

    (* Write the completed script to the guest. *)
    let firstboot_script = Buffer.contents fb in
    Firstboot.add_firstboot_script ~prog g inspect.i_root 1 firstboot_script

  and configure_rhev_apt fb =
    (* Configure RHEV-APT (the RHEV guest agent).  However if it doesn't
     * exist just warn about it and continue.
     *)
    match rhev_apt_exe with
    | None -> ()
    | Some rhev_apt_exe ->
      g#upload rhev_apt_exe "/rhev-apt.exe"; (* XXX *)

      bprintf fb "\
echo installing rhev-apt
\"\\rhev-apt.exe\" /S /v /qn

echo starting rhev-apt
net start rhev-apt
"

  and unconfigure_xenpv fb =
    match xenpv_uninst with
    | None -> () (* nothing to be uninstalled *)
    | Some uninst ->
      bprintf fb "\
echo uninstalling Xen PV driver
\"%s\"
" uninst
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

    if verbose then printf "current ControlSet is %s\n%!" current_cs;

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

    (* See if the drivers for this guest are available in virtio_win_dir. *)
    let path =
      match inspect.i_arch,
      inspect.i_major_version, inspect.i_minor_version,
      inspect.i_product_variant with
      | "i386", 5, 1, _ ->
        Some (virtio_win_dir // "drivers/i386/WinXP")
      | "i386", 5, 2, _ ->
        Some (virtio_win_dir // "drivers/i386/Win2003")
      | "i386", 6, 0, _ ->
        Some (virtio_win_dir // "drivers/i386/Win2008")
      | "i386", 6, 1, _ ->
        Some (virtio_win_dir // "drivers/i386/Win7")
      | "i386", 6, 2, _ ->
        Some (virtio_win_dir // "drivers/i386/Win8")
      | "i386", 6, 3, _ ->
        Some (virtio_win_dir // "drivers/i386/Win8.1")

      | "x86_64", 5, 2, _ ->
        Some (virtio_win_dir // "drivers/amd64/Win2003")
      | "x86_64", 6, 0, _ ->
        Some (virtio_win_dir // "drivers/amd64/Win2008")
      | "x86_64", 6, 1, "Client" ->
        Some (virtio_win_dir // "drivers/amd64/Win7")
      | "x86_64", 6, 1, "Server" ->
        Some (virtio_win_dir // "drivers/amd64/Win2008R2")
      | "x86_64", 6, 2, "Client" ->
        Some (virtio_win_dir // "drivers/amd64/Win8")
      | "x86_64", 6, 2, "Server" ->
        Some (virtio_win_dir // "drivers/amd64/Win2012")
      | "x86_64", 6, 3, "Client" ->
        Some (virtio_win_dir // "drivers/amd64/Win8.1")
      | "x86_64", 6, 3, "Server" ->
        Some (virtio_win_dir // "drivers/amd64/Win2012R2")

      | _ ->
        None in

    let path =
      match path with
      | None -> None
      | Some path ->
        if is_directory path then Some path else None in

    match path with
    | None ->
      warning ~prog (f_"there are no virtio drivers available for this version of Windows (%d.%d %s %s).  virt-v2v looks for drivers in %s\n\nThe guest will be configured to use slower emulated devices.")
        inspect.i_major_version inspect.i_minor_version
        inspect.i_arch inspect.i_product_variant
        virtio_win_dir;
      ( IDE, RTL8139 )

    | Some path ->
      (* Can we install the block driver? *)
      let block : guestcaps_block_type =
        let block_path = path // "viostor.sys" in
        if not (Sys.file_exists block_path) then (
          warning ~prog (f_"there is no viostor (virtio block device) driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver here: %s\n\nThe guest will be configured to use a slower emulated device.")
            inspect.i_major_version inspect.i_minor_version
            inspect.i_arch block_path;
          IDE
        )
        else (
          let target = sprintf "%s/system32/drivers/viostor.sys" systemroot in
          let target = g#case_sensitive_path target in
          g#upload block_path target;
          add_viostor_to_critical_device_database root current_cs;
          Virtio_blk
        ) in

      (* Can we install the virtio-net driver? *)
      let net : guestcaps_net_type =
        let net_path = path // "netkvm.inf" in
        if not (Sys.file_exists net_path) then (
          warning ~prog (f_"there is no virtio network driver for this version of Windows (%d.%d %s).  virt-v2v looks for this driver here: %s\n\nThe guest will be configured to use a slower emulated device.")
            inspect.i_major_version inspect.i_minor_version
            inspect.i_arch net_path;
          RTL8139
        )
        else
          (* It will be installed at firstboot. *)
          Virtio_net in

      (* Copy the drivers to the driverdir.  They will be installed at
       * firstboot.
       *)
      let files = Sys.readdir path in
      let files = Array.to_list files in
      let files = List.sort compare files in
      List.iter (
        fun file ->
          g#upload (path // file) (driverdir // file)
      ) files;

      (block, net)

  and add_viostor_to_critical_device_database root current_cs =
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
      warning ~prog (f_"could not find registry key HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion")

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

    (* Check that the root device contains NTFS magic. *)
    let magic = g#pread_device rootpart 8 3L in
    if magic = "NTFS    " then (
      (* Get the size of the whole disk containing the root partition. *)
      let rootdev = g#part_to_dev rootpart in (* eg. /dev/sda *)
      let size = g#blockdev_getsize64 rootdev in

      let heads =                       (* refer to the table above *)
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
  in

  (* Firstboot configuration. *)
  configure_firstboot ();

  (* Open the system hive and update it. *)
  let block_driver, net_driver =
    with_hive "system" ~write:true update_system_hive in

  (* Open the software hive and update it. *)
  with_hive "software" ~write:true update_software_hive;

  fix_ntfs_heads ();

  (* Return guest capabilities. *)
  let guestcaps = {
    gcaps_block_bus = block_driver;
    gcaps_net_bus = net_driver;
    (* Old virt-v2v would always present a QXL video display to converted
     * guests.  Unclear if this is correct.  XXX
     *)
    gcaps_video = QXL;
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
