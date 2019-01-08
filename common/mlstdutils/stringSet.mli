(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

type elt = String.t
type t = Set.Make(String).t

val empty : t
val is_empty : t -> bool
val mem : elt -> t -> bool
val add : elt -> t -> t
val singleton: elt -> t
val remove: elt -> t -> t
val union: t -> t -> t
val inter: t -> t -> t
val diff: t -> t -> t
val compare: t -> t -> int
val equal: t -> t -> bool
val subset: t -> t -> bool
val iter: (elt -> unit) -> t -> unit
(*val map: (elt -> elt) -> t -> t*)
val fold: (elt -> 'a -> 'a) -> t -> 'a -> 'a
val for_all: (elt -> bool) -> t -> bool
val exists: (elt -> bool) -> t -> bool
val filter: (elt -> bool) -> t -> t
val partition: (elt -> bool) -> t -> t * t
val cardinal: t -> int
val elements: t -> elt list
val min_elt: t -> elt
val max_elt: t -> elt
val choose: t -> elt
val split: elt -> t -> t * bool * t
