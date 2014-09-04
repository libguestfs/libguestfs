(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(* Poor man's JSON generator. *)

open Printf

open Common_utils

type field = string * json_t
and json_t = String of string | Int of int
and doc = field list

(* JSON quoting. *)
let json_quote str =
  let str = replace_str str "\\" "\\\\" in
  let str = replace_str str "\"" "\\\"" in
  let str = replace_str str "'" "\\'" in
  let str = replace_str str "\008" "\\b" in
  let str = replace_str str "\012" "\\f" in
  let str = replace_str str "\n" "\\n" in
  let str = replace_str str "\r" "\\r" in
  let str = replace_str str "\t" "\\t" in
  let str = replace_str str "\011" "\\v" in
  str

let string_of_doc fields =
  "{ " ^
    String.concat ", " (
      List.map (
        function
        | (n, String v) ->
          sprintf "\"%s\" : \"%s\"" n (json_quote v)
        | (n, Int v) ->
          sprintf "\"%s\" : %d" n v
      ) fields
    )
  ^ " }"
