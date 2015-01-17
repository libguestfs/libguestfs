(* virt-builder
 * Copyright (C) 2013-2015 Red Hat Inc.
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

(** This module represents a local cache. *)

val clean_cachedir : string -> unit
(** [clean_cachedir dir] clean the specified cache directory. *)

type t
(** The abstract data type. *)

val create : verbose:bool -> directory:string -> t
(** Create the abstract type. *)

val cache_of_name : t -> string -> string -> int -> string
(** [cache_of_name t name arch revision] return the filename
    of the cached file.  (Note: It doesn't check if the filename
    exists, this is just a simple string transformation). *)

val is_cached : t -> string -> string -> int -> bool
(** [is_cached t name arch revision] return whether the file with
    specified name, architecture and revision is cached. *)

val print_item_status : t -> header:bool -> (string * string * int) list -> unit
(** [print_item_status t header items] print the status in the cache
    of the specified items (which are tuples of name, architecture,
    and revision).

    If [~header:true] then display a header with the path of the
    cache. *)
