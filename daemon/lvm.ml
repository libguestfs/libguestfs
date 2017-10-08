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

open Unix
open Printf

open Std_utils

open Utils

let available = Optgroups.lvm2_available

(* Check whether lvs has -S to filter its output.
 * It is available only in lvm2 >= 2.02.107. 
 *)
let lvs_has_S_opt = lazy (
  let out = command "lvm" ["lvs"; "--help"] in
  String.find out "-S" >= 0
)

let rec lvs () =
  let has_S = Lazy.force lvs_has_S_opt in
  if has_S then (
    let out = command "lvm" ["lvs";
                             "-o"; "vg_name,lv_name";
                             "-S"; "lv_role=public && lv_skip_activation!=yes";
                             "--noheadings";
                             "--separator"; "/"] in
    convert_lvm_output ~prefix:"/dev/" out
  )
  else (
    let out = command "lvm" ["lvs";
                             "-o"; "lv_attr,vg_name,lv_name";
                             "--noheadings";
                             "--separator"; ":"] in
    filter_convert_old_lvs_output out
  )

and convert_lvm_output ?prefix out =
  let lines = String.nsplit "\n" out in

  (* Skip leading and trailing ("pvs", I'm looking at you) whitespace. *)
  let lines = List.map String.trim lines in

  (* Skip empty lines. *)
  let lines = List.filter ((<>) "") lines in

  (* Ignore "unknown device" message (RHBZ#1054761). *)
  let lines = List.filter ((<>) "unknown device") lines in

  (* Add a prefix? *)
  let lines =
    match prefix with
    | None -> lines
    | Some prefix -> List.map ((^) prefix) lines in

  (* Sort and return. *)
  List.sort compare lines

(* Filter a colon-separated output of
 *   lvs -o lv_attr,vg_name,lv_name
 * removing thin layouts, and building the device path as we expect it.
 *
 * This is used only when lvm has no -S.
 *)
and filter_convert_old_lvs_output out =
  let lines = String.nsplit "\n" out in
  let lines = List.map String.trim lines in
  let lines = List.filter ((<>) "") lines in
  let lines = List.filter ((<>) "unknown device") lines in

  let lines = List.filter_map (
    fun line ->
      match String.nsplit ":" line with
      | [ lv_attr; vg_name; lv_name ] ->
         (* Ignore thin layouts (RHBZ#1278878). *)
         if String.length lv_attr > 0 && lv_attr.[0] = 't' then None
         (* Ignore activationskip (RHBZ#1306666). *)
         else if String.length lv_attr > 9 && lv_attr.[9] = 'k' then None
         else
           Some (sprintf "/dev/%s/%s" vg_name lv_name)
      | _ ->
         None
  ) lines in

  List.sort compare lines

(* Convert a non-canonical LV path like /dev/mapper/vg-lv or /dev/dm-0
 * to a canonical one.
 *
 * This is harder than it should be.  A LV device like /dev/VG/LV is
 * really a symlink to a device-mapper device like /dev/dm-0.  However
 * at the device-mapper (kernel) level, nothing is really known about
 * LVM (a userspace concept).  Therefore we use a convoluted method to
 * determine this, by listing out known LVs and checking whether the
 * rdev (major/minor) of the device we are passed matches any of them.
 *
 * Note use of 'stat' instead of 'lstat' so that symlinks are fully
 * resolved.
 *)
let lv_canonical device =
  let stat1 = stat device in
  let lvs = lvs () in
  try
    Some (
      List.find (
        fun lv ->
          let stat2 = stat lv in
          stat1.st_rdev = stat2.st_rdev
      ) lvs
    )
  with
  | Not_found -> None
