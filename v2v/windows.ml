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

(* Detect anti-virus (AV) software installed in Windows guests. *)
let rex_virus     = Str.regexp_case_fold "virus" (* generic *)
let rex_kaspersky = Str.regexp_case_fold "kaspersky"
let rex_mcafee    = Str.regexp_case_fold "mcafee"
let rex_norton    = Str.regexp_case_fold "norton"
let rex_sophos    = Str.regexp_case_fold "sophos"
let rex_avg_tech  = Str.regexp_case_fold "avg technologies" (* RHBZ#1261436 *)

let rec detect_antivirus { Types.i_type = t; i_apps = apps } =
  assert (t = "windows");
  List.exists check_app apps

and check_app { Guestfs.app2_name = name;
                app2_publisher = publisher } =
  name      =~ rex_virus     ||
  name      =~ rex_kaspersky ||
  name      =~ rex_mcafee    ||
  name      =~ rex_norton    ||
  name      =~ rex_sophos    ||
  publisher =~ rex_avg_tech

and (=~) str rex =
  try ignore (Str.search_forward rex str 0); true with Not_found -> false

(* Copy the matching drivers to the driverdir; return true if any have
 * been copied.
 *)
let rec copy_virtio_drivers g inspect virtio_win driverdir =
  let ret = ref false in
  if is_directory virtio_win then (
    let cmd = sprintf "cd %s && find -type f" (quote virtio_win) in
    let paths = external_command cmd in
    List.iter (
      fun path ->
        if virtio_iso_path_matches_guest_os path inspect then (
          let source = virtio_win // path in
          let target = driverdir //
                         String.lowercase_ascii (Filename.basename path) in
          if verbose () then
            printf "Copying virtio driver bits: 'host:%s' -> '%s'\n"
                   source target;

          g#write target (read_whole_file source);
          ret := true
        )
      ) paths
  )
  else if is_regular_file virtio_win then (
    try
      let g2 = open_guestfs ~identifier:"virtio_win" () in
      g2#add_drive_opts virtio_win ~readonly:true;
      g2#launch ();
      let vio_root = "/" in
      g2#mount_ro "/dev/sda" vio_root;
      let paths = g2#find vio_root in
      Array.iter (
        fun path ->
          let source = vio_root // path in
          if g2#is_file source ~followsymlinks:false &&
               virtio_iso_path_matches_guest_os path inspect then (
            let target = driverdir //
                           String.lowercase_ascii (Filename.basename path) in
            if verbose () then
              printf "Copying virtio driver bits: '%s:%s' -> '%s'\n"
                     virtio_win path target;

            g#write target (g2#read_file source);
            ret := true
          )
        ) paths;
      g2#close()
    with Guestfs.Error msg ->
      error (f_"%s: cannot open virtio-win ISO file: %s") virtio_win msg
  );
  !ret

(* Given a path of a file relative to the root of the directory tree
 * with virtio-win drivers, figure out if it's suitable for the
 * specific Windows flavor of the current guest.
 *)
and virtio_iso_path_matches_guest_os path inspect =
  let { Types.i_major_version = os_major; i_minor_version = os_minor;
        i_arch = arch; i_product_variant = os_variant } = inspect in
  try
    (* Lowercased path, since the ISO may contain upper or lowercase path
     * elements.
     *)
    let lc_path = String.lowercase_ascii path in
    let lc_basename = Filename.basename path in

    let extension =
      match last_part_of lc_basename '.' with
      | Some x -> x
      | None -> raise Not_found
    in

    (* Skip files without specific extensions. *)
    let extensions = ["cat"; "inf"; "pdb"; "sys"] in
    if not (List.mem extension extensions) then raise Not_found;

    (* Using the full path, work out what version of Windows
     * this driver is for.  Paths can be things like:
     * "NetKVM/2k12R2/amd64/netkvm.sys" or
     * "./drivers/amd64/Win2012R2/netkvm.sys".
     * Note we check lowercase paths.
     *)
    let pathelem elem = String.find lc_path ("/" ^ elem ^ "/") >= 0 in
    let p_arch =
      if pathelem "x86" || pathelem "i386" then "i386"
      else if pathelem "amd64" then "x86_64"
      else raise Not_found in

    let is_client os_variant = os_variant = "Client"
    and not_client os_variant = os_variant <> "Client"
    and any_variant os_variant = true in
    let p_os_major, p_os_minor, match_os_variant =
      if pathelem "xp" || pathelem "winxp" then
        (5, 1, any_variant)
      else if pathelem "2k3" || pathelem "win2003" then
        (5, 2, any_variant)
      else if pathelem "vista" then
        (6, 0, is_client)
      else if pathelem "2k8" || pathelem "win2008" then
        (6, 0, not_client)
      else if pathelem "w7" || pathelem "win7" then
        (6, 1, is_client)
      else if pathelem "2k8r2" || pathelem "win2008r2" then
        (6, 1, not_client)
      else if pathelem "w8" || pathelem "win8" then
        (6, 2, is_client)
      else if pathelem "2k12" || pathelem "win2012" then
        (6, 2, not_client)
      else if pathelem "w8.1" || pathelem "win8.1" then
        (6, 3, is_client)
      else if pathelem "2k12r2" || pathelem "win2012r2" then
        (6, 3, not_client)
      else if pathelem "w10" || pathelem "win10" then
        (10, 0, is_client)
      else
        raise Not_found in

    arch = p_arch && os_major = p_os_major && os_minor = p_os_minor &&
      match_os_variant os_variant

  with Not_found -> false

(* The following function is only exported for unit tests. *)
module UNIT_TESTS = struct
  let virtio_iso_path_matches_guest_os = virtio_iso_path_matches_guest_os
end

(* This is a wrapper that handles opening and closing the hive
 * properly around a function [f].  If [~write] is [true] then the
 * hive is opened for writing and committed at the end if the
 * function returned without error.
 *)
type ('a, 'b) maybe = Either of 'a | Or of 'b

let with_hive (g : Guestfs.guestfs) hive_filename ~write f =
  let verbose = verbose () in
  g#hivex_open ~write ~verbose (* ~debug:verbose *) hive_filename;
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
 * point.  Returns [None] if the node is not found.
 *)
let rec get_node (g : Guestfs.guestfs) node = function
  | [] -> Some node
  | x :: xs ->
     let node = g#hivex_node_get_child node x in
     if node = 0L then None
     else get_node g node xs
