(* JSON parser
 * Copyright (C) 2015-2019 Red Hat Inc.
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

val json_parser_tree_parse : string -> JSON.json_t
(** Parse the JSON string. *)

val json_parser_tree_parse_file : string -> JSON.json_t
(** Parse the JSON in the specified file. *)

val object_get_string : string -> JSON.json_t -> string
(** [object_get_string key yv] gets the value of the [key] field as a string
    in the [yv] structure *)

val object_find_object : string -> JSON.json_t -> JSON.json_t
(** [object_get_object key yv] gets the value of the [key] field as a JSON
    value in the [yv] structure.

    Mind the returned type is different from [object_get_object] *)

val object_get_object : string -> JSON.json_t -> (string * JSON.json_t) list
(** [object_get_object key yv] gets the value of the [key] field as a JSON
    object in the [yv] structure *)

val object_get_number : string -> JSON.json_t -> int64
(** [object_get_number key yv] gets the value of the [key] field as an
    integer in the [yv] structure *)

val objects_get_string : string -> JSON.json_t list -> string
(** [objects_get_string key yvs] gets the value of the [key] field as a string
    in an [yvs] list of JSON.json_t structure.

    The key may not be found at all in the list, in which case an error
    is raised *)

val object_find_objects : ((string * JSON.json_t) -> 'a option) -> JSON.json_t -> 'a list
(** [object_find_objects fn obj] returns all the JSON objects matching the [fn]
    function in [obj] list. *)
