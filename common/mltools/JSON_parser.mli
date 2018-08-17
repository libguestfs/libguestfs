(* JSON parser
 * Copyright (C) 2015-2018 Red Hat Inc.
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

type json_parser_val =
| JSON_parser_null
| JSON_parser_string of string
| JSON_parser_number of int64
| JSON_parser_double of float
| JSON_parser_object of (string * json_parser_val) array
| JSON_parser_array of json_parser_val array
| JSON_parser_bool of bool

val json_parser_tree_parse : string -> json_parser_val
(** Parse the JSON string. *)

val object_get_string : string -> json_parser_val -> string
(** [object_get_string key yv] gets the value of the [key] field as a string
    in the [yv] structure *)

val object_find_object : string -> json_parser_val -> json_parser_val
(** [object_get_object key yv] gets the value of the [key] field as a JSON
    value in the [yv] structure.

    Mind the returned type is different from [object_get_object] *)

val object_get_object : string -> json_parser_val -> (string * json_parser_val) array
(** [object_get_object key yv] gets the value of the [key] field as a JSON
    object in the [yv] structure *)

val object_get_number : string -> json_parser_val -> int64
(** [object_get_number key yv] gets the value of the [key] field as an
    integer in the [yv] structure *)

val objects_get_string : string -> json_parser_val list -> string
(** [objects_get_string key yvs] gets the value of the [key] field as a string
    in an [yvs] list of json_parser_val structure.

    The key may not be found at all in the list, in which case an error
    is raised *)

val object_find_objects : ((string * json_parser_val) -> 'a option) -> json_parser_val -> 'a list
(** [object_find_objects fn obj] returns all the JSON objects matching the [fn]
    function in [obj] list. *)
