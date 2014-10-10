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

(* Simple JSON generator. *)

type field = string * json_t
and json_t =
  | String of string
  | Int of int
  | Int64 of int64
  | Bool of bool
  | List of json_t list
  | Dict of field list
and doc = field list

type output_format =
  | Compact
  | Indented


let spaces_for_indent level =
  let len = level * 2 in
  let s = String.create len in
  String.fill s 0 len ' ';
  s

let print_dict_after_start ~fmt ~indent ~size =
  match size, fmt with
    | 0, Compact -> ""
    | _, Compact -> " "
    | _, Indented -> "\n"

let print_dict_before_end ~fmt ~indent ~size =
  match size, fmt with
    | 0, _ -> ""
    | _, Compact -> " "
    | _, Indented -> "\n"

let print_indent ~fmt ~indent =
  match fmt with
  | Compact -> ""
  | Indented -> spaces_for_indent indent

(* JSON quoting. *)
let json_escape_string str =
  let res = ref "" in
  for i = 0 to String.length str - 1 do
    res := !res ^ (match str.[i] with
      | '"' -> "\\\""
      | '\\' -> "\\\\"
      | '\b' -> "\\b"
      | '\n' -> "\\n"
      | '\r' -> "\\r"
      | '\t' -> "\\t"
      | c -> String.make 1 c)
  done;
  !res

let json_quote_string str =
  "\"" ^ (json_escape_string str) ^ "\""

let rec output_dict fields ~fmt ~indent =
  let size = List.length fields in
  let newlinesep =
    match fmt with
    | Compact -> ", "
    | Indented -> ",\n" in
  "{" ^ (print_dict_after_start ~fmt ~indent ~size) ^
    String.concat newlinesep (
      List.map (
        fun (n, f) ->
          (print_indent ~fmt ~indent:(indent + 1)) ^ (json_quote_string n)
          ^ ": " ^ (output_field ~fmt ~indent f)
      ) fields
    )
  ^ (print_dict_before_end ~fmt ~indent ~size) ^ (print_indent ~fmt ~indent) ^ "}"

and output_list fields ~fmt ~indent =
  let size = List.length fields in
  let newlinesep =
    match fmt with
    | Compact -> ", "
    | Indented -> ",\n" in
  "[" ^ (print_dict_after_start ~fmt ~indent ~size) ^
    String.concat newlinesep (
      List.map (
        fun f ->
          (print_indent ~fmt ~indent:(indent + 1)) ^ (output_field ~fmt ~indent f)
      ) fields
    )
  ^ (print_dict_before_end ~fmt ~indent ~size) ^ (print_indent ~fmt ~indent) ^ "]"

and output_field ~indent ~fmt = function
  | String s -> json_quote_string s
  | Int i -> string_of_int i
  | Bool b -> if b then "true" else "false"
  | Int64 i -> Int64.to_string i
  | List l -> output_list ~indent:(indent + 1) ~fmt l
  | Dict d -> output_dict ~indent:(indent + 1) ~fmt d

let string_of_doc ?(fmt = Compact) fields =
  output_dict fields ~fmt ~indent:0
