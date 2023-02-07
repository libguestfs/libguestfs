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
open Mountable
open Inspect_types

let re_primary_partition = PCRE.compile "^/dev/(?:h|s|v)d.[1234]$"

let rec inspect_os () =
  Mount_utils.umount_all ();

  (* Iterate over all detected filesystems.  Inspect each one in turn. *)
  let fses = Listfs.list_filesystems () in

  let fses =
    List.filter_map (
      fun (mountable, vfs_type) ->
        Inspect_fs.check_for_filesystem_on mountable vfs_type
  ) fses in
  if verbose () then (
    eprintf "inspect_os: fses:\n";
    List.iter (fun fs -> eprintf "%s" (string_of_fs fs)) fses;
    flush stderr
  );

  (* The OS inspection information for CoreOS are gathered by inspecting
   * multiple filesystems. Gather all the inspected information in the
   * inspect_fs struct of the root filesystem.
   *)
  let fses = collect_coreos_inspection_info fses in

  (* Check if the same filesystem was listed twice as root in fses.
   * This may happen for the *BSD root partition where an MBR partition
   * is a shadow of the real root partition probably /dev/sda5
   *)
  let fses = check_for_duplicated_bsd_root fses in

  (* For Linux guests with a separate /usr filesystem, merge some of the
   * inspected information in that partition to the inspect_fs struct
   * of the root filesystem.
   *)
  let fses = collect_linux_inspection_info fses in

  (* Save what we found in a global variable. *)
  Inspect_types.inspect_fses := fses;

  (* At this point we have, in the handle, a list of all filesystems
   * found and data about each one.  Now we assemble the list of
   * filesystems which are root devices.
   *
   * Fall through to inspect_get_roots to do that.
   *)
  inspect_get_roots ()

(* Traverse through the filesystem list and find out if it contains
 * the [/] and [/usr] filesystems of a CoreOS image. If this is the
 * case, sum up all the collected information on the root fs.
 *)
and collect_coreos_inspection_info fses =
  (* Split the list into CoreOS root(s), CoreOS usr(s), and
   * everything else.
   *)
  let rec loop roots usrs others = function
    | [] -> roots, usrs, others
    | ({ role = RoleRoot { distro = Some DISTRO_COREOS } } as r) :: rest ->
       loop (r::roots) usrs others rest
    | ({ role = RoleUsr { distro = Some DISTRO_COREOS } } as u) :: rest ->
       loop roots (u::usrs) others rest
    | o :: rest ->
       loop roots usrs (o::others) rest
  in
  let roots, usrs, others = loop [] [] [] fses in

  match roots with
  (* If there are no CoreOS roots, then there's nothing to do. *)
  | [] -> fses
  (* If there are more than one CoreOS roots, we cannot inspect the guest. *)
  | _::_::_ -> failwith "multiple CoreOS root filesystems found"
  | [root] ->
     match usrs with
     (* If there are no CoreOS usr partitions, nothing to do. *)
     | [] -> fses
     | usrs ->
        (* CoreOS is designed to contain 2 /usr partitions (USR-A, USR-B):
         * https://coreos.com/docs/sdk-distributors/sdk/disk-partitions/
         * One is active and one passive. During the initial boot, the
         * passive partition is empty and it gets filled up when an
         * update is performed.  Then, when the system reboots, the
         * boot loader is instructed to boot from the passive partition.
         * If both partitions are valid, we cannot determine which the
         * active and which the passive is, unless we peep into the
         * boot loader. As a workaround, we check the OS versions and
         * pick the one with the higher version as active.
         *)
        let compare_versions u1 u2 =
          let v1 =
            match u1 with
            | { role = RoleUsr { version = Some v } } -> v
            | _ -> (0, 0) in
          let v2 =
            match u2 with
            | { role = RoleUsr { version = Some v } } -> v
            | _ -> (0, 0) in
          compare v2 v1 (* reverse order *)
        in
        let usrs = List.sort compare_versions usrs in
        let usr = List.hd usrs in

        merge usr root;
        root :: others

(* On *BSD systems, sometimes [/dev/sda[1234]] is a shadow of the
 * real root filesystem that is probably [/dev/sda5] (see:
 * [http://www.freebsd.org/doc/handbook/disk-organization.html])
 *)
and check_for_duplicated_bsd_root fses =
  try
    let is_primary_partition = function
      | { m_type = (MountablePath | MountableBtrfsVol _) } -> false
      | { m_type = MountableDevice; m_device = d } ->
         PCRE.matches re_primary_partition d
    in

    (* Try to find a "BSD primary", if there is one. *)
    let bsd_primary =
      List.find (
        function
        | { fs_location = { mountable };
            role = RoleRoot { os_type = Some t } } ->
           (t = OS_TYPE_FREEBSD || t = OS_TYPE_NETBSD || t = OS_TYPE_OPENBSD)
           && is_primary_partition mountable
        | _ -> false
      ) fses in

    let bsd_primary_os_type =
      match bsd_primary with
      | { role = RoleRoot { os_type = Some t } } -> t
      | _ -> assert false in

    (* Try to find a shadow of the primary, and if it is found the
     * primary is removed.
     *)
    let fses_without_bsd_primary = List.filter ((!=) bsd_primary) fses in
    let shadow_exists =
      List.exists (
        function
        | { role = RoleRoot { os_type = Some t } } ->
           t = bsd_primary_os_type
        | _ -> false
      ) fses_without_bsd_primary in
    if shadow_exists then fses_without_bsd_primary else fses
  with
    Not_found -> fses

(* Traverse through the filesystem list and find out if it contains
 * the [/] and [/usr] filesystems of a Linux image (but not CoreOS,
 * for which there is a separate [collect_coreos_inspection_info]).
 *
 * If this is the case, sum up all the collected information on each
 * root fs from the respective [/usr] filesystems.
 *)
and collect_linux_inspection_info fses =
  List.map (
    function
    | { role = RoleRoot { distro = Some DISTRO_COREOS } } as root -> root
    | { role = RoleRoot _ } as root ->
       collect_linux_inspection_info_for fses root
    | fs -> fs
  ) fses

(* Traverse through the filesystems and find the /usr filesystem for
 * the specified C<root>: if found, merge its basic inspection details
 * to the root when they were set (i.e. because the /usr had os-release
 * or other ways to identify the OS).
 *)
and collect_linux_inspection_info_for fses root =
  let root_fstab =
    match root with
    | { role = RoleRoot { fstab = f } } -> f
    | _ -> assert false in

  try
    let usr =
      List.find (
        function
        | { role = RoleUsr _; fs_location = usr_mp } ->
           (* This checks that this usr is found in the fstab of
            * the root filesystem.
            *)
           List.exists (
             fun (mountable, _) ->
               usr_mp.mountable = mountable
           ) root_fstab
        | _ -> false
      ) fses in

    eprintf "collect_linux_inspection_info_for: merging:\n%sinto:\n%s"
      (string_of_fs usr) (string_of_fs root);
    merge usr root;
    root
  with
    Not_found -> root

and inspect_get_roots () =
  let fses = !Inspect_types.inspect_fses in

  let roots =
    List.filter_map (
      fun fs -> try Some (root_of_fs fs) with Invalid_argument _ -> None
    ) fses in
  if verbose () then (
    eprintf "inspect_get_roots: roots:\n";
    List.iter (fun root -> eprintf "%s" (string_of_root root)) roots;
    flush stderr
  );

  (* Only return the list of mountables, since subsequent calls will
   * be used to retrieve the other information.
   *)
  List.map (fun { root_location = { mountable = m } } -> m) roots

and root_of_fs =
  function
  | { fs_location = location; role = RoleRoot data } ->
     { root_location = location; inspection_data = data }
  | { role = (RoleUsr _ | RoleSwap | RoleOther) } ->
     invalid_arg "root_of_fs"

and inspect_get_mountpoints root_mountable =
  let root = search_for_root root_mountable in
  let fstab = root.inspection_data.fstab in

  (* If no fstab information (Windows) return just the root. *)
  if fstab = [] then
    [ "/", root_mountable ]
  else (
    List.filter_map (
      fun (mountable, mp) ->
        if String.length mp > 0 && mp.[0] = '/' then
          Some (mp, mountable)
        else
          None
    ) fstab
  )

and inspect_get_filesystems root_mountable =
  let root = search_for_root root_mountable in
  let fstab = root.inspection_data.fstab in

  (* If no fstab information (Windows) return just the root. *)
  if fstab = [] then
    [ root_mountable ]
  else
    List.map fst fstab

and inspect_get_format root = "installed"

and inspect_get_type root =
  let root = search_for_root root in
  match root.inspection_data.os_type with
  | Some v -> string_of_os_type v
  | None -> "unknown"

and inspect_get_distro root =
  let root = search_for_root root in
  match root.inspection_data.distro with
  | Some v -> string_of_distro v
  | None -> "unknown"

and inspect_get_package_format root =
  let root = search_for_root root in
  match root.inspection_data.package_format with
  | Some v -> string_of_package_format v
  | None -> "unknown"

and inspect_get_package_management root =
  let root = search_for_root root in
  match root.inspection_data.package_management with
  | Some v -> string_of_package_management v
  | None -> "unknown"

and inspect_get_product_name root =
  let root = search_for_root root in
  match root.inspection_data.product_name with
  | Some v -> v
  | None -> "unknown"

and inspect_get_product_variant root =
  let root = search_for_root root in
  match root.inspection_data.product_variant with
  | Some v -> v
  | None -> "unknown"

and inspect_get_major_version root =
  let root = search_for_root root in
  match root.inspection_data.version with
  | Some (major, _) -> major
  | None -> 0

and inspect_get_minor_version root =
  let root = search_for_root root in
  match root.inspection_data.version with
  | Some (_, minor) -> minor
  | None -> 0

and inspect_get_arch root =
  let root = search_for_root root in
  match root.inspection_data.arch with
  | Some v -> v
  | None -> "unknown"

and inspect_get_hostname root =
  let root = search_for_root root in
  match root.inspection_data.hostname with
  | Some v -> v
  | None -> "unknown"

and inspect_get_build_id root =
  let root = search_for_root root in
  match root.inspection_data.build_id with
  | Some v -> v
  | None -> "unknown"

and inspect_get_windows_systemroot root =
  let root = search_for_root root in
  match root.inspection_data.windows_systemroot with
  | Some v -> v
  | None ->
     failwith "not a Windows guest, or systemroot could not be determined"

and inspect_get_windows_system_hive root =
  let root = search_for_root root in
  match root.inspection_data.windows_system_hive with
  | Some v -> v
  | None ->
     failwith "not a Windows guest, or system hive not found"

and inspect_get_windows_software_hive root =
  let root = search_for_root root in
  match root.inspection_data.windows_software_hive with
  | Some v -> v
  | None ->
     failwith "not a Windows guest, or software hive not found"

and inspect_get_windows_current_control_set root =
  let root = search_for_root root in
  match root.inspection_data.windows_current_control_set with
  | Some v -> v
  | None ->
     failwith "not a Windows guest, or CurrentControlSet could not be determined"

and inspect_is_live root = false

and inspect_is_netinst root = false

and inspect_is_multipart root = false

and inspect_get_drive_mappings root =
  let root = search_for_root root in
  root.inspection_data.drive_mappings

and search_for_root root =
  let fses = !Inspect_types.inspect_fses in
  if fses = [] then
    failwith "no inspection data: call guestfs_inspect_os first";

  let root =
    try
      List.find (
        function
        | { fs_location = { mountable = m }; role = RoleRoot _ } -> root = m
        | _ -> false
      ) fses
    with
      Not_found ->
        failwithf "%s: root device not found: only call this function with a root device previously returned by guestfs_inspect_os"
                  (Mountable.to_string root) in

  root_of_fs root
