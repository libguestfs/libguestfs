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
open Unix

open Std_utils

open Utils

let map_block_devices ~return_md f =
  let devs = Sys.readdir "/sys/block" in
  let devs = Array.to_list devs in
  let devs = List.filter (
    fun dev ->
      String.is_prefix dev "sd" ||
      String.is_prefix dev "hd" ||
      String.is_prefix dev "ubd" ||
      String.is_prefix dev "vd" ||
      String.is_prefix dev "sr" ||
      (return_md && String.is_prefix dev "md" &&
         String.length dev >= 3 && Char.isdigit dev.[2])
  ) devs in

  (* Ignore the root device. *)
  let devs =
    List.filter (fun dev -> not (is_root_device ("/dev/" ^ dev))) devs in

  (* RHBZ#514505: Some versions of qemu <= 0.10 add a
   * CD-ROM device even though we didn't request it.  Try to
   * detect this by seeing if the device contains media.
   *)
  let devs =
    List.filter (
      fun dev ->
        try
          let fd = openfile ("/dev/" ^ dev) [O_RDONLY; O_CLOEXEC] 0 in
          close fd;
          true
        with _ -> false
    ) devs in

  (* Call the map function for the devices left in the list. *)
  List.map f devs

let list_devices () =
  (* For backwards compatibility, don't return MD devices in the list
   * returned by guestfs_list_devices.  This is because most API users
   * expect that this list is effectively the same as the list of
   * devices added by guestfs_add_drive.
   *
   * Also, MD devices are special devices - unlike the devices exposed
   * by QEMU, and there is a special API for them,
   * guestfs_list_md_devices.
   *)
  let devices =
    map_block_devices ~return_md:false ((^) "/dev/") in
  sort_device_names devices

let rec list_partitions () =
  let partitions = map_block_devices ~return_md:true add_partitions in
  let partitions = List.flatten partitions in
  sort_device_names partitions

and add_partitions dev =
  (* Open the device's directory under /sys/block *)
  let parts = Sys.readdir ("/sys/block/" ^ dev) in
  let parts = Array.to_list parts in

  (* Look in /sys/block/<device>/ for entries starting with
   * <device>, eg. /sys/block/sda/sda1.
   *)
  let parts = List.filter (fun part -> String.is_prefix part dev) parts in
  List.map ((^) "/dev/") parts

let nr_devices () = List.length (list_devices ())

let part_to_dev part =
  let dev, part = split_device_partition part in
  if part = 0 then
    failwithf "device name is not a partition";
  "/dev/" ^ dev

let part_to_partnum part =
  let _, part = split_device_partition part in
  if part = 0 then
    failwithf "device name is not a partition";
  part

let is_whole_device device =
  (* A 'whole' block device will have a symlink to the device in its
   * /sys/block directory
   *)
  assert (String.is_prefix device "/dev/");
  let device = String.sub device 5 (String.length device - 5) in
  let devpath = sprintf "/sys/block/%s/device" device in

  try ignore (stat devpath); true
  with Unix_error ((ENOENT|ENOTDIR), _, _) -> false

let device_index device =
  (* This is the algorithm which was used by the C version.  Why
   * can't we use drive_index from C_utils?  XXX
   *)
  let rec loop i = function
    | [] -> failwithf "%s: device not found" device
    | dev :: devices when dev = device -> i
    | _ :: devices -> loop (i+1) devices
  in
  loop 0 (list_devices ())
