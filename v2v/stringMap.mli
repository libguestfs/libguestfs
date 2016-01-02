(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

type key = String.t
type 'a t = 'a Map.Make(String).t

val empty : 'a t
val is_empty : 'a t -> bool
val mem : key -> 'a t -> bool
val add : key -> 'a -> 'a t -> 'a t
(*
val singleton : key -> 'a -> 'a t
*)
val remove : key -> 'a t -> 'a t
(*
val merge : (key -> 'a option -> 'b option -> 'c option) -> 'a t -> 'b t -> 'c t
*)
val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int
val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
val iter : (key -> 'a -> unit) -> 'a t -> unit
val fold : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
(*
val for_all : (key -> 'a -> bool) -> 'a t -> bool
val exists : (key -> 'a -> bool) -> 'a t -> bool
val filter : (key -> 'a -> bool) -> 'a t -> 'a t
val partition : (key -> 'a -> bool) -> 'a t -> 'a t * 'a t
val cardinal : 'a t -> int
val bindings : 'a t -> (key * 'a) list
val min_binding : 'a t -> key * 'a
val max_binding : 'a t -> key * 'a
val choose : 'a t -> key * 'a
val split : key -> 'a t -> 'a t * 'a option * 'a t
*)
val find : key -> 'a t -> 'a
val map : ('a -> 'b) -> 'a t -> 'b t
(*
val mapi : (key -> 'a -> 'b) -> 'a t -> 'b t
*)
val keys : 'a t -> key list
