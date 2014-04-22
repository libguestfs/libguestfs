(* virt-builder
 * Copyright (C) 2013-2014 Red Hat Inc.
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

type sections = section list
and section = string * fields                (* [name] + fields *)
and fields = field list
and field = string * string option * string  (* key + subkey + value *)

(* Types returned by the C index parser. *)
type c_sections = c_section array
and c_section = string * c_fields             (* [name] + fields *)
and c_fields = field array

(* Calls yyparse in the C code. *)
external parse_index : prog:string -> error_suffix:string -> string -> c_sections = "virt_builder_parse_index"

let read_ini ~prog ?(error_suffix = "") file =
  let sections = parse_index ~prog ~error_suffix file in
  let sections = Array.to_list sections in
  List.map (
    fun (n, fields) ->
      n, Array.to_list fields
  ) sections
