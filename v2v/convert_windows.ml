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

let convert verbose (g : G.guestfs) inspect source =
  (* Get the data directory. *)
  let virt_tools_data_dir =
    try Sys.getenv "VIRT_TOOLS_DATA_DIR"
    with Not_found -> Config.datadir // "virt-tools" in
  let virtio_win_dir = "/usr/share/virtio-win" in

  (* Since this is a Windows guest, RHSrvAny must exist.  (Check also
   * that it's not a dangling symlink but a real file).
   *)
  let rhsrvany_exe = virt_tools_data_dir // "rhsrvany.exe" in
  (try
    let chan = open_in rhsrvany_exe in
    close_in chan
   with
     Sys_error msg ->
       error (f_"'%s' is missing.  This file is required in order to do Windows conversions.  You can get it by building rhsrvany (https://github.com/rwmjones/rhsrvany).  Original error: %s")
         rhsrvany_exe msg
  );

  let systemroot = g#inspect_get_windows_systemroot inspect.i_root in

  (* This is a wrapper that handles opening and closing the hive
   * properly around a function [f].  If [~write] is [true] then the
   * hive is opened for writing and committed at the end if the
   * function returned without error.
   *)
  let rec with_hive name ~write f =
    let filename = sprintf "%s/system32/config/%s" systemroot name in
    let filename = g#case_sensitive_path filename in
    g#hivex_open ~write ~verbose ~debug:verbose filename;
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

  (* Take a 7 bit ASCII string and encode it as UTF16LE. *)
  and encode_utf16le str =
    let len = String.length str in
    let copy = String.make (len*2) '\000' in
    for i = 0 to len-1 do
      String.unsafe_set copy (i*2) (String.unsafe_get str i)
    done;
    copy

  (* Take a UTF16LE string and decode it to UTF-8.  Actually this
   * fails if the string is not 7 bit ASCII.  XXX Use iconv here.
   *)
  and decode_utf16le str =
    let len = String.length str in
    if len mod 2 <> 0 then
      error (f_"decode_utf16le: Windows string does not appear to be in UTF16-LE encoding.  This could be a bug in virt-v2v.");
    let copy = String.create (len/2) in
    for i = 0 to (len/2)-1 do
      let cl = String.unsafe_get str (i*2) in
      let ch = String.unsafe_get str ((i*2)+1) in
      if ch != '\000' || Char.code cl >= 127 then
        error (f_"decode_utf16le: Windows UTF16-LE string contains non-7-bit characters.  This is a bug in virt-v2v, please report it.");
      String.unsafe_set copy i cl
    done;
    copy
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

  (* Open the software hive (readonly) and find the Xen PV uninstaller,
   * if it exists.
   *)
  let xenpv_uninst = with_hive "software" ~write:false find_xenpv_uninst in

  (*----------------------------------------------------------------------*)
  (* Perform the conversion of the Windows guest. *)

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

    let firstboot = configure_firstboot root current_cs in
    configure_rhev_apt root firstboot;
    (match xenpv_uninst with
    | None -> () (* nothing to be uninstalled *)
    | Some uninst -> unconfigure_xenpv root firstboot uninst
    );
    close_firstboot root firstboot;
    disable_services root current_cs;
    let block_net_drivers = install_virtio_drivers root current_cs in

    block_net_drivers

  and configure_firstboot root current_cs =
    ignore virt_tools_data_dir;
    ()




  and configure_rhev_apt root firstboot =
    ()



  and unconfigure_xenpv root firstboot uninst_exe =
    ()





  and close_firstboot root firstboot =
    ()





  and disable_services root current_cs =
    ()





  and install_virtio_drivers root current_cs =
    ignore virtio_win_dir;
    ("XXX", "XXX")





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
    (* XXX display *)
  } in

  guestcaps
