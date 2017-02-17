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

let with_hive_readonly (g : Guestfs.guestfs) hive_filename f =
  let verbose = verbose () in
  g#hivex_open ~write:false ~unsafe:true ~verbose (* ~debug:verbose *)
               hive_filename;
  protect ~f:(
    fun () ->
      let root = g#hivex_root () in
      f root
  ) ~finally:g#hivex_close

let with_hive_write (g : Guestfs.guestfs) hive_filename f =
  let verbose = verbose () in
  g#hivex_open ~write:true ~verbose (* ~debug:verbose *) hive_filename;
  protect ~f:(
    fun () ->
      let root = g#hivex_root () in
      let ret = f root in
      g#hivex_commit None;
      ret
  ) ~finally:g#hivex_close

(* Find the given node in the current hive, relative to the starting
 * point.  Returns [None] if the node is not found.
 *)
let rec get_node (g : Guestfs.guestfs) node = function
  | [] -> Some node
  | x :: xs ->
     let node = g#hivex_node_get_child node x in
     if node = 0L then None
     else get_node g node xs
