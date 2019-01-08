(* virt-builder
 * Copyright (C) 2013-2019 Red Hat Inc.
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

(* Utilities/common functions used in virt-builder only. *)

open Printf

open Std_utils
open Tools_utils

type gpgkey_type =
  | No_Key
  | Fingerprint of string
  | KeyFile of string
and revision =
  | Rev_int of int
  | Rev_string of string

let string_of_revision = function
  | Rev_int n -> string_of_int n
  | Rev_string s -> s

let increment_revision = function
  | Rev_int n -> Rev_int (n + 1)
  | Rev_string s -> Rev_int ((int_of_string s) + 1)

let get_image_infos filepath =
  let qemuimg_cmd = "qemu-img info --output json " ^ quote filepath in
  let lines = external_command qemuimg_cmd in
  let line = String.concat "\n" lines in
  JSON_parser.json_parser_tree_parse line
