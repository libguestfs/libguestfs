(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

(** {1 Parallel xzcat (or fall back to regular xzcat).}

    Eventually regular xzcat will be able to work in parallel and this
    code can go away.
*)

val pxzcat : string -> string -> unit
    (** [pxzcat input output] uncompresses the file [input] to the file
        [output].  The input and output must both be seekable.

        If liblzma was found at compile time, this uses an internal
        implementation of parallel xzcat.  Otherwise regular xzcat is
        used. *)

val using_parallel_xzcat : unit -> bool
(** Returns [true] iff the implementation uses parallel xzcat. *)
