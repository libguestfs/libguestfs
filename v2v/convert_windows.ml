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

let convert ~keep_serial_console (g : G.guestfs) inspect source =
  (* Get the data directory. *)
  let virt_tools_data_dir =
    try Sys.getenv "VIRT_TOOLS_DATA_DIR"
    with Not_found -> Guestfs_config.datadir // "virt-tools" in

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

  (* Get the Windows %systemroot%. *)
  let systemroot = g#inspect_get_windows_systemroot inspect.i_root in

  (* Get the software and system hive files. *)
  let software_hive_filename =
    let filename = sprintf "%s/system32/config/software" systemroot in
    let filename = g#case_sensitive_path filename in
    filename in

  let system_hive_filename =
    let filename = sprintf "%s/system32/config/system" systemroot in
    let filename = g#case_sensitive_path filename in
    filename in

  (*----------------------------------------------------------------------*)
  (* Inspect the Windows guest. *)

  (* If the Windows guest appears to be using group policy. *)
  let has_group_policy =
    Windows.with_hive_readonly g software_hive_filename
      (fun root ->
       try
         let path = ["Microsoft"; "Windows"; "CurrentVersion";
                     "Group Policy"; "History"]  in
         let node =
           match Windows.get_node g root path with
           | None -> raise Not_found
           | Some node -> node in
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
      ) in

  (* If the Windows guest has AV installed. *)
  let has_antivirus = Windows.detect_antivirus inspect in

  (* Open the software hive (readonly) and find the Xen PV uninstaller,
   * if it exists.
   *)
  let xenpv_uninst =
    let xenpvreg = "Red Hat Paravirtualized Xen Drivers for Windows(R)" in

    Windows.with_hive_readonly g software_hive_filename
      (fun root ->
       try
         let path = ["Microsoft"; "Windows"; "CurrentVersion"; "Uninstall";
                     xenpvreg] in
         let node =
           match Windows.get_node g root path with
           | None -> raise Not_found
           | Some node -> node in
         let uninstkey = "UninstallString" in
         let valueh = g#hivex_node_get_value node uninstkey in
         if valueh = 0L then (
           warning (f_"cannot uninstall Xen PV drivers: registry key 'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\%s' does not contain an '%s' key")
                   xenpvreg uninstkey;
           raise Not_found
         );
         let data = g#hivex_value_value valueh in
         let data = Regedit.decode_utf16le data in

         (* The uninstall program will be uninst.exe.  This is a wrapper
          * around _uninst.exe which prompts the user.  As we don't want
          * the user to be prompted, we run _uninst.exe explicitly.
          *)
         let len = String.length data in
         let data =
           if len >= 8 &&
              String.lowercase_ascii (String.sub data (len-8) 8) = "uninst.exe"
           then
             (String.sub data 0 (len-8)) ^ "_uninst.exe"
           else
             data in

         Some data
       with
         Not_found -> None
      ) in

  (* Locate and retrieve all uninstallation commands for Parallels Tools *)
  let prltools_uninsts =
    let uninsts = ref [] in

    Windows.with_hive_readonly g software_hive_filename
      (fun root ->
       try
         let path = ["Microsoft"; "Windows"; "CurrentVersion"; "Uninstall"] in
         let node =
           match Windows.get_node g root path with
           | None -> raise Not_found
           | Some node -> node in
         let uninstnodes = g#hivex_node_children node in

         Array.iter (
           fun { G.hivex_node_h = uninstnode } ->
             try
               let valueh = g#hivex_node_get_value uninstnode "DisplayName" in
               if valueh = 0L then
                 raise Not_found;

               let dispname = g#hivex_value_utf8 valueh in
               if not (Str.string_match (Str.regexp ".*Parallels Tools.*")
                                        dispname 0) then
                 raise Not_found;

               let uninstval = "UninstallString" in
               let valueh = g#hivex_node_get_value uninstnode uninstval in
               if valueh = 0L then (
                 let name = g#hivex_node_name uninstnode in
                 warning (f_"cannot uninstall Parallels Tools: registry key 'HKLM\\SOFTWARE\\%s\\%s' with DisplayName '%s' doesn't contain value '%s'")
                         (String.concat "\\" path) name dispname uninstval;
                 raise Not_found
               );

               let uninst = (g#hivex_value_utf8 valueh) ^
                     " /quiet /norestart /l*v+ \"%~dpn0.log\"" ^
                     " REBOOT=ReallySuppress REMOVE=ALL" ^
                     (* without these custom Parallels-specific MSI properties the
                      * uninstaller still shows a no-way-out reboot dialog *)
                     " PREVENT_REBOOT=Yes LAUNCHED_BY_SETUP_EXE=Yes" in

               uninsts := uninst :: !uninsts
             with
               Not_found -> ()
         ) uninstnodes
       with
         Not_found -> ()
      );

    !uninsts
  in

  (*----------------------------------------------------------------------*)
  (* Perform the conversion of the Windows guest. *)

  let rec configure_firstboot () =
    configure_rhev_apt ();
    unconfigure_xenpv ();
    unconfigure_prltools ()

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

  and unconfigure_prltools () =
    List.iter (
      fun uninst ->
        let fb_script = "\
@echo off

echo uninstalling Parallels guest tools
" ^ uninst ^
(* ERROR_SUCCESS_REBOOT_REQUIRED == 3010 is OK too *)
"
if errorlevel 3010 exit /b 0
" in

        Firstboot.add_firstboot_script g inspect.i_root
          "uninstall Parallels tools" fb_script
    ) prltools_uninsts
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
    Windows_virtio.install_drivers g inspect systemroot
                                   root current_cs

  and disable_services root current_cs =
    (* Disable miscellaneous services. *)
    let services = Windows.get_node g root [current_cs; "Services"] in

    match services with
    | None -> ()
    | Some services ->
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
             (* Delete the node instead of trying to disable it (RHBZ#737600) *)
             g#hivex_node_delete_child node
           )
         ) disable

  and disable_autoreboot root current_cs =
    (* If the guest reboots after a crash, it's hard to see the original
     * error (eg. the infamous 0x0000007B).  Turn off autoreboot.
     *)
    let crash_control =
      Windows.get_node g root [current_cs; "Control"; "CrashControl"] in
    match crash_control with
    | None -> ()
    | Some crash_control ->
       g#hivex_node_set_value crash_control "AutoReboot" 4_L (le32_of_int 0_L)

  and update_software_hive root =
    (* Update the SOFTWARE hive.  When this function is called the
     * hive has already been opened as a hivex handle inside
     * guestfs.
     *)

    (* Find the node \Microsoft\Windows\CurrentVersion.  If the node
     * has a key called DevicePath then append the virtio driver
     * path to this key.
     *)
    let node =
      Windows.get_node g root ["Microsoft"; "Windows"; "CurrentVersion"] in
    match node with
    | Some node ->
       let append = Regedit.encode_utf16le ";%SystemRoot%\\Drivers\\VirtIO" in
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
              if String.find data append = -1 then (
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
    | None ->
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

  (* Open the system hive for writes and update it. *)
  let block_driver, net_driver, video_driver =
    Windows.with_hive_write g system_hive_filename update_system_hive in

  (* Open the software hive for writes and update it. *)
  Windows.with_hive_write g software_hive_filename update_software_hive;

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

(* Register this conversion module. *)
let () =
  let matching = function
    | { i_type = "windows" } -> true
    | _ -> false
  in
  Modules_list.register_convert_module matching "windows" convert
