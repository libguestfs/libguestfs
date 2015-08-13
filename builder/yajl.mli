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

val yajl_is_available : unit -> bool
(** Is YAJL built in? If not, calling any of the other yajl_*
    functions will result in an error. *)

val yajl_tree_parse : string -> yajl_val
(** Parse the JSON string. *)
