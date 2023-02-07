(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Utils
open Inspect_types
open Inspect_utils

(* Check a predefined list of common windows system root locations. *)
let systemroot_paths =
  [ "/windows"; "/winnt"; "/win32"; "/win"; "/reactos" ]

let re_boot_ini_os =
  PCRE.compile "^(multi|scsi)\\((\\d+)\\)disk\\((\\d+)\\)rdisk\\((\\d+)\\)partition\\((\\d+)\\)([^=]+)="

let rec check_windows_root data =
  let systemroot =
    match get_windows_systemroot () with
    | None -> assert false (* Should never happen - see caller. *)
    | Some systemroot -> systemroot in

  data.os_type <- Some OS_TYPE_WINDOWS;
  data.distro <- Some DISTRO_WINDOWS;
  data.windows_systemroot <- Some systemroot;
  data.arch <- Some (check_windows_arch systemroot);

  (* Load further fields from the Windows registry. *)
  check_windows_registry systemroot data

and is_windows_systemroot () =
  get_windows_systemroot () <> None

and get_windows_systemroot () =
  let rec loop = function
    | [] -> None
    | path :: paths ->
       let path = case_sensitive_path_silently path in
       match path with
       | None -> loop paths
       | Some path ->
          if is_systemroot path then Some path
          else loop paths
  in
  let systemroot = loop systemroot_paths in

  let systemroot =
    match systemroot with
    | Some systemroot -> Some systemroot
    | None ->
       (* If the fs contains boot.ini, check it for non-standard
        * systemroot locations.
        *)
       let boot_ini_path = case_sensitive_path_silently "/boot.ini" in
       match boot_ini_path with
       | None -> None
       | Some boot_ini_path ->
          get_windows_systemroot_from_boot_ini boot_ini_path in

  match systemroot with
  | None -> None
  | Some systemroot ->
     if verbose () then
       eprintf "get_windows_systemroot: windows %%SYSTEMROOT%% = %s\n%!"
               systemroot;
     Some systemroot

and get_windows_systemroot_from_boot_ini boot_ini_path =
  let chroot = Chroot.create ~name:"get_windows_systemroot_from_boot_ini" () in
  let lines = Chroot.f chroot read_small_file boot_ini_path in
  match lines with
  | None -> None
  | Some lines ->
     (* Find:
      *   [operating systems]
      * followed by multiple lines starting with "multi" or "scsi".
      *)
     let rec loop = function
       | [] -> None
       | str :: rest when String.is_prefix str "[operating systems]" ->
          let rec loop2 = function
            | [] -> []
            | str :: rest when String.is_prefix str "multi(" ||
                               String.is_prefix str "scsi(" ->
               str :: loop2 rest
            | _ -> []
          in
          Some (loop2 rest)
       | _ :: rest -> loop rest
     in
     match loop lines with
     | None -> None
     | Some oses ->
        (* Rewrite multi|scsi lines, removing any which we cannot parse. *)
        let oses =
          List.filter_map (
            fun line ->
              if PCRE.matches re_boot_ini_os line then (
                let ctrlr_type = PCRE.sub 1
                and ctrlr = int_of_string (PCRE.sub 2)
                and disk = int_of_string (PCRE.sub 3)
                and rdisk = int_of_string (PCRE.sub 4)
                and part = int_of_string (PCRE.sub 5)
                and path = PCRE.sub 6 in

                (* Swap backslashes for forward slashes in the
                 * system root path.
                 *)
                let path = String.replace_char path '\\' '/' in

                Some (ctrlr_type, ctrlr, disk, rdisk, part, path)
              )
              else None
          ) oses in

        (* The Windows system root may be on any disk. However, there
         * are currently (at least) 2 practical problems preventing us
         * from locating it on another disk:
         *
         * 1. We don't have enough metadata about the disks we were
         * given to know if what controller they were on and what
         * index they had.
         *
         * 2. The way inspection of filesystems currently works, we
         * can't mark another filesystem, which we may have already
         * inspected, to be inspected for a specific Windows system
         * root.
         *
         * Solving 1 properly would require a new API at a minimum. We
         * might be able to fudge something practical without this,
         * though, e.g. by looking at the <partition>th partition of
         * every disk for the specific windows root.
         *
         * Solving 2 would probably require a significant refactoring
         * of the way filesystems are inspected. We should probably do
         * this some time.
         *
         * For the moment, we ignore all partition information and
         * assume the system root is on the current partition. In
         * practice, this will normally be correct.
         *)

        let rec loop = function
          | [] -> None
          | (_, _, _, _, _, path) :: rest ->
             if is_systemroot path then Some path
             else loop rest
        in
        loop oses

(* Try to find Windows systemroot using some common locations.
 *
 * Notes:
 *
 * (1) We check for some directories inside to see if it is a real
 * systemroot, and not just a directory that happens to have the same
 * name.
 *
 * (2) If a Windows guest has multiple disks and applications are
 * installed on those other disks, then those other disks will contain
 * "/Program Files" and "/System Volume Information".  Those would
 * *not* be Windows root disks.  (RHBZ#674130)
 *)
and is_systemroot systemroot =
  is_dir_nocase (systemroot ^ "/system32") &&
  is_dir_nocase (systemroot ^ "/system32/config") &&
  is_file_nocase (systemroot ^ "/system32/cmd.exe")

(* Return the architecture of the guest from cmd.exe. *)
and check_windows_arch systemroot =
  let cmd_exe = sprintf "%s/system32/cmd.exe" systemroot in

  (* Should exist because of previous check above in is_systemroot. *)
  let cmd_exe = Realpath.case_sensitive_path cmd_exe in

  Filearch.file_architecture cmd_exe

(* Read further fields from the Windows registry. *)
and check_windows_registry systemroot data =
  (* We know (from is_systemroot) that the config directory exists. *)
  let software_hive = sprintf "%s/system32/config/software" systemroot in
  let software_hive = Realpath.case_sensitive_path software_hive in
  let software_hive =
    if Is.is_file software_hive then Some software_hive else None in
  data.windows_software_hive <- software_hive;

  let system_hive = sprintf "%s/system32/config/system" systemroot in
  let system_hive = Realpath.case_sensitive_path system_hive in
  let system_hive =
    if Is.is_file system_hive then Some system_hive else None in
  data.windows_system_hive <- system_hive;

  match software_hive, system_hive with
  | None, _ | Some _, None -> ()
  | Some software_hive, Some system_hive ->
     (* Check software hive. *)
     check_windows_software_registry software_hive data;

     (* Check system hive. *)
     check_windows_system_registry system_hive data

(* At the moment, pull just the ProductName and version numbers from
 * the registry.  In future there is a case for making many more
 * registry fields available to callers.
 *)
and check_windows_software_registry software_hive data =
  with_hive (Sysroot.sysroot_path software_hive) (
    fun h root ->
      try
        let path = [ "Microsoft"; "Windows NT"; "CurrentVersion" ] in
        let node = get_node h root path in
        let values = Hivex.node_values h node in
        let values = Array.to_list values in
        (* Convert to a list of (key, value) to make the following easier. *)
        let values = List.map (fun v -> Hivex.value_key h v, v) values in

        (* Look for ProductName key. *)
        (try
           let v = List.assoc "ProductName" values in
           data.product_name <- Some (Hivex.value_string h v)
         with
           Not_found -> ()
        );

        (* Version is complicated.  Use CurrentMajorVersionNumber and
         * CurrentMinorVersionNumber if present.  If they are not
         * found, fall back on CurrentVersion.
         *)
        (try
           let major_v = List.assoc "CurrentMajorVersionNumber" values
           and minor_v = List.assoc "CurrentMinorVersionNumber" values in
           let major = Int32.to_int (Hivex.value_dword h major_v)
           and minor = Int32.to_int (Hivex.value_dword h minor_v) in
           data.version <- Some (major, minor)
         with
           Not_found ->
           let v = List.assoc "CurrentVersion" values in
           let v = Hivex.value_string h v in
           parse_version_from_major_minor v data
        );

        (* InstallationType (product_variant). *)
        (try
           let v = List.assoc "InstallationType" values in
           data.product_variant <- Some (Hivex.value_string h v)
         with
           Not_found -> ()
        );

        (* CurrentBuildNumber (build_id).
         *
         * In modern Windows, the "CurrentBuild" and "CurrentBuildNumber"
         * keys are the same.  But in Windows XP, "CurrentBuild"
         * contained something quite different.  So always use
         * "CurrentBuildNumber".
         *)
        (try
           let v = List.assoc "CurrentBuildNumber" values in
           data.build_id <- Some (Hivex.value_string h v)
         with
           Not_found -> ()
        );
      with
      | Not_found ->
         if verbose () then
           eprintf "check_windows_software_registry: cannot locate HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\n%!"
  ) (* with_hive *)

and check_windows_system_registry system_hive data =
  with_hive (Sysroot.sysroot_path system_hive) (
    fun h root ->
      get_drive_mappings h root data;

      let current_control_set = get_current_control_set h root in
      data.windows_current_control_set <- current_control_set;

      match current_control_set with
      | None -> ()
      | Some current_control_set ->
         let hostname = get_hostname h root current_control_set in
         data.hostname <- hostname
  ) (* with_hive *)

(* Get the CurrentControlSet. *)
and get_current_control_set h root =
  try
    let path = [ "Select" ] in
    let node = get_node h root path in
    let current_v = Hivex.node_get_value h node "Current" in
    let current_control_set =
      sprintf "ControlSet%03ld" (Hivex.value_dword h current_v) in
    Some current_control_set
  with
  | Not_found ->
     if verbose () then
       eprintf "check_windows_system_registry: cannot locate HKLM\\SYSTEM\\Select\n%!";
     None

(* Get the drive mappings.
 * This page explains the contents of HKLM\System\MountedDevices:
 * http://www.goodells.net/multiboot/partsigs.shtml
 *)
and get_drive_mappings h root data =
  let devices = lazy (Devsparts.list_devices ()) in
  let partitions = lazy (Devsparts.list_partitions ()) in
  try
    let path = [ "MountedDevices" ] in
    let node = get_node h root path in
    let values = Hivex.node_values h node in
    let values = Array.to_list values in
    let values =
      List.filter_map (
        fun value ->
          let key = Hivex.value_key h value in
          let keylen = String.length key in
          if keylen >= 14 &&
             String.lowercase_ascii (String.sub key 0 12) = "\\dosdevices\\" &&
             Char.isalpha key.[12] && key.[13] = ':' then (
            let drive_letter = String.sub key 12 1 in

            (* Get the binary value.  Is it a fixed disk? *)
            let (typ, blob) = Hivex.value_value h value in
            let device =
              if typ = Hivex.REG_BINARY then (
                if String.length blob >= 24 &&
                   String.is_prefix blob "DMIO:ID:" (* GPT *) then
                  map_registry_disk_blob_gpt (Lazy.force partitions) blob
                else if String.length blob = 12 then
                  map_registry_disk_blob_mbr (Lazy.force devices) blob
                else
                  None
              )
              else None in

            match device with
            | None -> None
            | Some device -> Some (drive_letter, device)
          )
          else
            None
      ) values in

    data.drive_mappings <- values

  with
  | Not_found ->
     if verbose () then
       eprintf "check_windows_system_registry: cannot find drive mappings\n%!"

(* Windows Registry HKLM\SYSTEM\MountedDevices uses a blob of data
 * to store partitions.  This blob is described here:
 * http://www.goodells.net/multiboot/partsigs.shtml
 * The following function maps this blob to a libguestfs partition
 * name, if possible.
 *)
and map_registry_disk_blob_mbr devices blob =
  try
    (* First 4 bytes are the disk ID.  Search all devices to find the
     * disk with this disk ID.
     *)
    let diskid = String.sub blob 0 4 in
    let device =
      List.find (
        fun dev ->
          Parted.part_get_parttype dev = "msdos" &&
            pread dev 4 0x01b8 = diskid
      ) devices in

    (* Next 8 bytes are the offset of the partition in bytes(!) given as
     * a 64 bit little endian number.  Luckily it's easy to get the
     * partition byte offset from Parted.part_list.
     *)
    let offset = String.sub blob 4 8 in
    let offset = int_of_le64 offset in
    let partitions = Parted.part_list device in
    let partition =
      List.find (fun { Structs.part_start = s } -> s = offset) partitions in

    (* Construct the full device name. *)
    Some (sprintf "%s%ld" device partition.Structs.part_num)
  with
  | Not_found -> None

(* Matches Windows registry HKLM\SYSYTEM\MountedDevices\DosDevices blob to
 * to libguestfs GPT partition device. For GPT disks, the blob is made of
 * "DMIO:ID:" prefix followed by the GPT partition GUID.
 *)
and map_registry_disk_blob_gpt partitions blob =
  (* The blob_guid is returned as a lowercase hex string. *)
  let blob_guid = extract_guid_from_registry_blob blob in

  if verbose () then
    eprintf "map_registry_disk_blob_gpt: searching for GUID %s\n%!"
            blob_guid;

  try
    let partition =
      List.find (
        fun part ->
          let partnum = Devsparts.part_to_partnum part in
          let device = Devsparts.part_to_dev part in
          let typ = Parted.part_get_parttype device in
          if typ <> "gpt" then false
          else (
            let guid = Parted.part_get_gpt_guid device partnum in
            String.lowercase_ascii guid = blob_guid
          )
      ) partitions in
    Some partition
  with
  | Not_found -> None

(* Extracts the binary GUID stored in blob from Windows registry
 * HKLM\SYSTYEM\MountedDevices\DosDevices value and converts it to a
 * GUID string so that it can be matched against libguestfs partition
 * device GPT GUID.
 *)
and extract_guid_from_registry_blob blob =
  (* Copy relevant sections from blob to respective ints.
   * Note we have to skip 8 byte "DMIO:ID:" prefix.
   *)
  let data1 = int_of_le32 (String.sub blob 8 4)
  and data2 = int_of_le16 (String.sub blob 12 2)
  and data3 = int_of_le16 (String.sub blob 14 2)
  and data4 = int_of_be64 (String.sub blob 16 8) (* really big endian! *) in

  (* Must be lowercase hex. *)
  sprintf "%08Lx-%04Lx-%04Lx-%04Lx-%012Lx"
          data1 data2 data3
          (Int64.shift_right_logical data4 48)
          (data4 &^ 0xffffffffffff_L)

and pread device size offset =
  let ret =
    with_openfile device [Unix.O_RDONLY; Unix.O_CLOEXEC] 0 (
      fun fd ->
        ignore (Unix.lseek fd offset Unix.SEEK_SET);
        let ret = Bytes.create size in
        if Unix.read fd ret 0 size < size then
          failwithf "pread: %s: short read" device;
        ret
    ) in
  Bytes.to_string ret

(* Get the hostname. *)
and get_hostname h root current_control_set =
  try
    let path = [ current_control_set; "Services"; "Tcpip"; "Parameters" ] in
    let node = get_node h root path in
    let values = Hivex.node_values h node in
    let values = Array.to_list values in
    (* Convert to a list of (key, value) to make the following easier. *)
    let values = List.map (fun v -> Hivex.value_key h v, v) values in
    let hostname_v = List.assoc "Hostname" values in
    Some (Hivex.value_string h hostname_v)
  with
  | Not_found ->
     if verbose () then
       eprintf "check_windows_system_registry: cannot locate HKLM\\SYSTEM\\%s\\Services\\Tcpip\\Parameters and/or Hostname key\n%!" current_control_set;
     None

(* Raises [Not_found] if the node is not found. *)
and get_node h node = function
  | [] -> node
  | x :: xs ->
     let node = Hivex.node_get_child h node x in
     get_node h node xs

(* NB: This function DOES NOT test for the existence of the file.  It
 * will return non-NULL even if the file/directory does not exist.
 * You have to call guestfs_is_file{,_opts} etc.
 *)
and case_sensitive_path_silently path =
  try
    Some (Realpath.case_sensitive_path path)
  with
  | exn ->
     if verbose () then
       eprintf "case_sensitive_path_silently: %s: %s\n%!" path
               (Printexc.to_string exn);
     None
