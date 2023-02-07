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

external is_raid_device : string -> bool =
  "guestfs_int_daemon_is_raid_device" [@@noalloc]

let re_md = PCRE.compile "^md[0-9]+$"

let list_md_devices () =
  (* Look for directories under /sys/block matching md[0-9]+
   * As an additional check, we also make sure they have a md subdirectory.
   *)
  let devs = Sys.readdir "/sys/block" in
  let devs = Array.to_list devs in
  let devs = List.filter (fun d -> PCRE.matches re_md d) devs in
  let devs = List.filter (
    fun d -> is_directory (sprintf "/sys/block/%s/md" d)
  ) devs in

  (* Construct the equivalent /dev/md[0-9]+ device names. *)
  let devs = List.map ((^) "/dev/") devs in

  (* Check they are really RAID devices. *)
  let devs = List.filter is_raid_device devs in

  (* Return the list sorted. *)
  sort_device_names devs

let md_detail md =
  let out = command "mdadm" ["-D"; "--export"; md] in

  (* Split the command output into lines. *)
  let out = String.trim out in
  let lines = String.nsplit "\n" out in

  (* Parse the output of mdadm -D --export:
   * MD_LEVEL=raid1
   * MD_DEVICES=2
   * MD_METADATA=1.0
   * MD_UUID=cfa81b59:b6cfbd53:3f02085b:58f4a2e1
   * MD_NAME=localhost.localdomain:0
   *)
  let values = parse_key_value_strings lines in
  List.map (
    fun (key, value) ->
      (* Remove the MD_ prefix from the key and translate the
       * remainder to lower case.
       *)
      let key =
        if String.is_prefix key "MD_" then
          String.sub key 3 (String.length key - 3)
        else
          key in
      let key = String.lowercase_ascii key in

      (* Add the key/value pair to the output. *)
      (key, value)
  ) values
