(** Basic counting module.

    Copyright (C) 2006 Merjis Ltd.

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
*)

type 'a t
(** Count items of type ['a]. *)

val create : unit -> 'a t
(** Create a new counter. *)

val incr : 'a t -> 'a -> unit
(** [incr counter thing] adds one to the count of [thing]s in [counter]. *)

val decr : 'a t -> 'a -> unit
(** [decr counter thing] subtracts one to the count of [thing]s in [counter]. *)

val add : 'a t -> 'a -> int -> unit
(** [add counter thing n] adds [n] to the count of [thing]s in [counter]. *)

val sub : 'a t -> 'a -> int -> unit
(** [sub counter thing n] subtracts [n] to the count of [thing]s in [counter]. *)

val set : 'a t -> 'a -> int -> unit
(** [set counter thing n] sets the count of [thing]s to [n]. *)

val get : 'a t -> 'a -> int
(** [get counter thing] returns the count of [thing]s.   (Returns 0 for
  * [thing]s which have not been added.
  *)

val incr_get : 'a t -> 'a -> int
(** Faster form of {!Counter.incr} followed by {!Counter.get}. *)

val zero : 'a t -> 'a -> unit
(** [zero counter thing] sets the count of [thing]s to 0.
  * See also {!Counter.clear}.
  *)

val read : 'a t -> (int * 'a) list
(** [read counter] reads the frequency of each thing.  They are sorted
  * with the thing appearing most frequently first.  Only things occurring
  * non-zero times are returned.
  *)

val length : 'a t -> int
(** Return the number of distinct things. See also {!Counter.total} *)

val total : 'a t -> int
(** Return the number of things counted (the total number of counts).
  * See also {!Counter.length}
  *)

val clear : 'a t -> unit
(** [clear counter] zeroes all counts. *)
