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

open Common_gettext.Gettext
open Common_utils

type yajl_val =
| Yajl_null
| Yajl_string of string
| Yajl_number of int64
| Yajl_double of float
| Yajl_object of (string * yajl_val) array
| Yajl_array of yajl_val array
| Yajl_bool of bool

external yajl_tree_parse : string -> yajl_val = "virt_builder_yajl_tree_parse"

let object_find_optional key = function
  | Yajl_object o ->
    (match List.filter (fun (k, _) -> k = key) (Array.to_list o) with
    | [(k, v)] -> Some v
    | [] -> None
    | _ -> error (f_"more than value for the key '%s'") key)
  | _ -> error (f_"the value of the key '%s' is not an object") key

let object_find key yv =
  match object_find_optional key yv with
  | None -> error (f_"missing value for the key '%s'") key
  | Some v -> v

let object_get_string key yv =
  match object_find key yv with
  | Yajl_string s -> s
  | _ -> error (f_"the value for the key '%s' is not a string") key

let object_find_object key yv =
  match object_find key yv with
  | Yajl_object _ as o -> o
  | _ -> error (f_"the value for the key '%s' is not an object") key

let object_find_objects fn = function
  | Yajl_object o -> filter_map fn (Array.to_list o)
  | _ -> error (f_"the value is not an object")

let object_get_object key yv =
  match object_find_object key yv with
  | Yajl_object o -> o
  | _ -> assert false (* object_find_object already errors out. *)

let object_get_number key yv =
  match object_find key yv with
  | Yajl_number n -> n
  | Yajl_double d -> Int64.of_float d
  | _ -> error (f_"the value for the key '%s' is not an integer") key

let objects_get_string key yvs =
  let rec loop = function
    | [] -> None
    | x :: xs ->
      (match object_find_optional key x with
      | Some (Yajl_string s) -> Some s
      | Some _ -> error (f_"the value for key '%s' is not a string as expected") key
      | None -> loop xs
      )
  in
  match loop yvs with
  | Some s -> s
  | None -> error (f_"the key '%s' was not found in a list of objects") key
