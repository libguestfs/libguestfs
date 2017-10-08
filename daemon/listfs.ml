(* guestfs-inspection
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

let rec list_filesystems () =
  let has_lvm2 = Lvm.available () in
  let has_ldm = Ldm.available () in

  let devices = Devsparts.list_devices () in
  let partitions = Devsparts.list_partitions () in
  let mds = Md.list_md_devices () in

  (* Look to see if any devices directly contain filesystems
   * (RHBZ#590167).  However vfs-type will fail to tell us anything
   * useful about devices which just contain partitions, so we also
   * get the list of partitions and exclude the corresponding devices
   * by using part-to-dev.
   *)
  let devices_containing_partitions = List.fold_left (
    fun set part ->
      StringSet.add (Devsparts.part_to_dev part) set
  ) StringSet.empty partitions in
  let devices = List.filter (
    fun dev ->
      not (StringSet.mem dev devices_containing_partitions)
  ) devices in

  (* Use vfs-type to check for filesystems on devices. *)
  let ret = List.filter_map check_with_vfs_type devices in

  (* Use vfs-type to check for filesystems on partitions, but
   * ignore MBR partition type 42 used by LDM.
   *)
  let ret =
    ret @
      List.filter_map (
        fun part ->
          if not has_ldm || not (is_mbr_partition_type_42 part) then
            check_with_vfs_type part
          else
            None                (* ignore type 42 *)
      ) partitions in

  (* Use vfs-type to check for filesystems on md devices. *)
  let ret = ret @ List.filter_map check_with_vfs_type mds in

  (* LVM. *)
  let ret =
    if has_lvm2 then (
      let lvs = Lvm.lvs () in
      (* Use vfs-type to check for filesystems on LVs. *)
      ret @ List.filter_map check_with_vfs_type lvs
    )
    else ret in

  (* LDM. *)
  let ret =
    if has_ldm then (
      let ldmvols = Ldm.list_ldm_volumes () in
      let ldmparts = Ldm.list_ldm_partitions () in
      (* Use vfs-type to check for filesystems on Windows dynamic disks. *)
      ret @
        List.filter_map check_with_vfs_type ldmvols @
        List.filter_map check_with_vfs_type ldmparts
    )
    else ret in

  List.flatten ret

(* Use vfs-type to check for a filesystem of some sort of [device].
 * Returns [Some [device, vfs_type; ...]] if found (there may be
 * multiple devices found in the case of btrfs), else [None] if nothing
 * is found.
 *)
and check_with_vfs_type device =
  let mountable = Mountable.of_device device in
  let vfs_type =
    try Blkid.vfs_type mountable
    with exn ->
       if verbose () then
         eprintf "check_with_vfs_type: %s: %s\n"
                 device (Printexc.to_string exn);
       "" in

  if vfs_type = "" then
    Some [mountable, "unknown"]

  (* Ignore all "*_member" strings.  In libblkid these are returned
   * for things which are members of some RAID or LVM set, most
   * importantly "LVM2_member" which is a PV.
   *)
  else if String.is_suffix vfs_type "_member" then
    None

  (* Ignore LUKS-encrypted partitions.  These are also containers, as above. *)
  else if vfs_type = "crypto_LUKS" then
    None

  (* A single btrfs device can turn into many volumes. *)
  else if vfs_type = "btrfs" then (
    let vols = Btrfs.btrfs_subvolume_list mountable in

    (* Filter out the default subvolume.  You can access that by
     * simply mounting the whole device, so we will add the whole
     * device at the beginning of the returned list instead.
     *)
    let default_volume = Btrfs.btrfs_subvolume_get_default mountable in
    let vols =
      List.filter (
        fun { Btrfs.btrfssubvolume_id = id } -> id <> default_volume
      ) vols in

    Some (
      (mountable, vfs_type) (* whole device = default volume *)
      :: List.map (
           fun { Btrfs.btrfssubvolume_path = path } ->
             let mountable = Mountable.of_btrfsvol device path in
             (mountable, "btrfs")
         ) vols
      )
  )

  else
    Some [mountable, vfs_type]

(* We should ignore partitions that have MBR type byte 0x42, because
 * these are members of a Windows dynamic disk group.  Trying to read
 * them will cause errors (RHBZ#887520).  Assuming that libguestfs was
 * compiled with ldm support, we'll get the filesystems on these later.
 *)
and is_mbr_partition_type_42 partition =
  try
    let partnum = Devsparts.part_to_partnum partition in
    let device = Devsparts.part_to_dev partition in
    let mbr_id = Parted.part_get_mbr_id device partnum in
    mbr_id = 0x42
  with exn ->
     if verbose () then
       eprintf "is_mbr_partition_type_42: %s: %s\n"
               partition (Printexc.to_string exn);
     false
