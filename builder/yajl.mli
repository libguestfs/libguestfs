(* virt-builder
 * Copyright (C) 2015 Red Hat Inc.
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

type yajl_val =
| Yajl_null
| Yajl_string of string
| Yajl_number of int64
| Yajl_double of float
| Yajl_object of (string * yajl_val) array
| Yajl_array of yajl_val array
| Yajl_bool of bool

val yajl_tree_parse : string -> yajl_val
(** Parse the JSON string. *)

val object_get_string : string -> yajl_val -> string
(** [object_get_string key yv] gets the value of the [key] field as a string
    in the [yv] structure *)

val object_find_object : string -> yajl_val -> yajl_val
(** [object_get_object key yv] gets the value of the [key] field as a yajl
    value in the [yv] structure.

    Mind the returned type is different from [object_get_object] *)

val object_get_object : string -> yajl_val -> (string * yajl_val) array
(** [object_get_object key yv] gets the value of the [key] field as a Yajl
    object in the [yv] structure *)

val object_get_number : string -> yajl_val -> int64
(** [object_get_number key yv] gets the value of the [key] field as an
    integer in the [yv] structure *)

val objects_get_string : string -> yajl_val list -> string
(** [objects_get_string key yvs] gets the value of the [key] field as a string
    in an [yvs] list of yajl_val structure.

    The key may not be found at all in the list, in which case an error
    is raised *)

val object_find_objects : ((string * yajl_val) -> 'a option) -> yajl_val -> 'a list
(** [object_find_objects fn obj] returns all the Yajl objects matching the [fn]
    function in [obj] list. *)
