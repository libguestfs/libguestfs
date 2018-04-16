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

open Common_utils
open Common_gettext.Gettext

module G = Guestfs

open Types

let rec inspect_source root_choice g =
  let roots = g#inspect_os () in
  let roots = Array.to_list roots in
  let root = choose_root root_choice g roots in

  reject_if_not_installed_image g root;

  let typ = g#inspect_get_type root in

  (* Mount up the filesystems. *)
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (
    fun (mp, dev) ->
      (try g#mount dev mp
       with G.Error msg ->
         if mp = "/" then ( (* RHBZ#1145995 *)
           if String.find msg "Windows" >= 0 && String.find msg "NTFS partition is in an unsafe state" >= 0 then
             error (f_"unable to mount the disk image for writing. This has probably happened because Windows Hibernation or Fast Restart is being used in this guest. You have to disable this (in the guest) in order to use virt-v2v.\n\nOriginal error message: %s") msg
           else
             error "%s" msg
         )
         else
           warning (f_"%s (ignored)") msg
      );

      (* Some filesystems (hello, ntfs-3g) can silently fall back to
       * a read-only mount.  Check the root filesystem is really writable.
       * RHBZ#1567763
       *)
      if mp = "/" then (
        let file = sprintf "/%s" (String.random8 ()) in
        (try g#touch file
         with G.Error msg ->
           if g#last_errno () = G.Errno.errno_EROFS then
             error (f_"filesystem was mounted read-only, even though we asked for it to be mounted read-write.  This usually means that the filesystem was not cleanly unmounted.  Possible causes include trying to convert a guest which is running, or using Windows Hibernation or Fast Restart.\n\nOriginal error message: %s") msg
           else
             error (f_"could not write to the guest filesystem: %s") msg
        );
        g#rm file
      )
  ) mps;

  (* Get list of applications/packages installed. *)
  let apps = g#inspect_list_applications2 root in
  let apps = Array.to_list apps in

  (* A map of app2_name -> application2, for easier lookups.  Note
   * that app names are not unique!  (eg. 'kernel' can appear multiple
   * times)
   *)
  let apps_map = List.fold_left (
    fun map app ->
      let name = app.G.app2_name in
      let vs = try StringMap.find name map with Not_found -> [] in
      StringMap.add name (app :: vs) map
  ) StringMap.empty apps in

  (* If the guest is Windows, get some Windows-specific inspection
   * data, else (for simplicity when accessing) use empty strings.
   *)
  let systemroot, software_hive, system_hive, current_cs =
    match typ with
    | "windows" ->
       g#inspect_get_windows_systemroot root,
       g#inspect_get_windows_software_hive root,
       g#inspect_get_windows_system_hive root,
       g#inspect_get_windows_current_control_set root
    | _ ->
       "", "", "", "" in

  let inspect = {
    i_root = root;
    i_type = typ;
    i_distro = g#inspect_get_distro root;
    i_osinfo = g#inspect_get_osinfo root;
    i_arch = g#inspect_get_arch root;
    i_major_version = g#inspect_get_major_version root;
    i_minor_version = g#inspect_get_minor_version root;
    i_package_format = g#inspect_get_package_format root;
    i_package_management = g#inspect_get_package_management root;
    i_product_name = g#inspect_get_product_name root;
    i_product_variant = g#inspect_get_product_variant root;
    i_mountpoints = mps;
    i_apps = apps;
    i_apps_map = apps_map;
    i_firmware = get_firmware_bootable_device g;
    i_windows_systemroot = systemroot;
    i_windows_software_hive = software_hive;
    i_windows_system_hive = system_hive;
    i_windows_current_control_set = current_cs;
  } in
  debug "%s" (string_of_inspect inspect);

  sanity_check_inspection inspect;

  inspect

and choose_root root_choice g = function
  | [] ->
     error (f_"inspection could not detect the source guest (or physical machine).\n\nAssuming that you are running virt-v2v/virt-p2v on a source which is supported (and not, for example, a blank disk), then this should not happen.\n\nNo root device found in this operating system image.");
  | [root] -> root (* only one root, so return it *)
  | roots ->
     (* If there are multiple roots, use the [--root] option supplied
      * by the user to help us choose what we should do next.
      *)
     match root_choice with
     | AskRoot ->
        (* List out the roots and ask the user to choose. *)
        printf "\n***\n";
        printf (f_"Dual- or multi-boot operating system detected.  Choose the root filesystem\nthat contains the main operating system from the list below:\n");
        printf "\n";
        iteri (
          fun i root ->
            let prod = g#inspect_get_product_name root in
            match prod with
            | "unknown" -> printf " [%d] %s\n" (i+1) root
            | prod -> printf " [%d] %s (%s)\n" (i+1) root prod
        ) roots;
        printf "\n";
        let i = ref 0 in
        let n = List.length roots in
        while !i < 1 || !i > n do
          printf (f_"Enter a number between 1 and %d, or 'exit': ") n;
          let input = read_line () in
          if input = "exit" || input = "q" || input = "quit" then
            exit 0
          else (
            try i := int_of_string input
            with
            | End_of_file -> error (f_"connection closed")
            | Failure _ -> ()
          )
        done;
        List.nth roots (!i - 1)

      | SingleRoot ->
        error (f_"multi-boot operating systems are not supported by virt-v2v. Use the --root option to change how virt-v2v handles this.")

      | FirstRoot ->
        let root = List.hd roots in
        info (f_"Picked %s because '--root first' was used.") root;
        root

      | RootDev dev ->
        let root =
          if List.mem dev roots then dev
          else
            error (f_"root device %s not found.  Roots found were: %s")
              dev (String.concat " " roots) in
        info (f_"Picked %s because '--root %s' was used.") root dev;
        root

(* Reject this OS if it doesn't look like an installed image. *)
and reject_if_not_installed_image g root =
  let fmt = g#inspect_get_format root in
  if fmt <> "installed" then
    error (f_"libguestfs thinks this is not an installed operating system (it might be, for example, an installer disk or live CD).  If this is wrong, it is probably a bug in libguestfs.  root=%s fmt=%s") root fmt

(* See if this guest could use UEFI to boot.  It should use GPT and
 * it should have an EFI System Partition (ESP).
 *
 * If it has ESP(s), then [UEFI devs] is returned where [devs] is the
 * list of at least one ESP.
 *
 * Otherwise, [BIOS] is returned.
 *)
and get_firmware_bootable_device g =
  let rec uefi_ESP_guid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
  and is_uefi_ESP dev part =
    let partnum = g#part_to_partnum part in
    g#part_get_gpt_type dev partnum = uefi_ESP_guid
  and parttype_is_gpt dev =
    try g#part_get_parttype dev = "gpt"
    with G.Error msg as exn ->
         (* If it's _not_ "unrecognised disk label" then re-raise it. *)
         if g#last_errno () <> G.Errno.errno_EINVAL then raise exn;
         debug "%s (ignored)" msg;
         false
  and is_uefi_bootable_part part =
    let dev = g#part_to_dev part in
    parttype_is_gpt dev && is_uefi_ESP dev part
  in

  let partitions = Array.to_list (g#list_partitions ()) in
  let partitions = List.filter is_uefi_bootable_part partitions in

  match partitions with
  | [] -> I_BIOS
  | partitions -> I_UEFI partitions

(* If some inspection fields are "unknown", then that indicates a
 * failure in inspection, and we shouldn't continue.  For an example
 * of this, see RHBZ#1278371.  However don't "assert" here, since
 * the user might have pointed virt-v2v at a blank disk.  Give an
 * error message instead.
 *)
and sanity_check_inspection inspect =
  error_if_unknown "i_type" inspect.i_type;
  error_if_unknown "i_distro" inspect.i_distro;
  error_if_unknown "i_arch" inspect.i_arch

and error_if_unknown fieldname value =
  if value = "unknown" then
    error (f_"inspection could not detect the source guest (or physical machine).\n\nAssuming that you are running virt-v2v/virt-p2v on a source which is supported (and not, for example, a blank disk), then this should not happen.\n\nInspection field '%s' was 'unknown'.")
          fieldname
