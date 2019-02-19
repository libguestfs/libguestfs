(* virt-v2v
 * Copyright (C) 2019 Red Hat Inc.
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

open Std_utils

exception Invalid_variable of string

let var_re = PCRE.compile "(^|[^%])%{([^}]+)}"

let check_variable var =
  String.iter (
    function
    | '0'..'9'
    | 'a'..'z'
    | 'A'..'Z'
    | '_'
    | '-' -> ()
    | _ -> raise (Invalid_variable var)
  ) var

let scan_variables str =
  let res = ref [] in
  let offset = ref 0 in
  while PCRE.matches ~offset:!offset var_re str; do
    let var = PCRE.sub 2 in
    check_variable var;
    let _, end_ = PCRE.subi 0 in
    List.push_back res var;
    offset := end_
  done;
  List.remove_duplicates !res

let replace_fn str fn =
  let res = ref str in
  let offset = ref 0 in
  while PCRE.matches ~offset:!offset var_re !res; do
    let var = PCRE.sub 2 in
    check_variable var;
    let start_, end_ = PCRE.subi 0 in
    match fn var with
    | None ->
      offset := end_
    | Some text ->
      let prefix_len =
        let prefix_start, prefix_end = PCRE.subi 1 in
        prefix_end - prefix_start in
      res := (String.sub !res 0 (start_ + prefix_len)) ^ text ^ (String.sub !res end_ (String.length !res - end_));
      offset := start_ + prefix_len + String.length text
  done;
  !res

let replace_list str lst =
  let fn var =
    try Some (List.assoc var lst)
    with Not_found -> None
  in
  replace_fn str fn
