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

type csum_t =
| SHA256 of string
| SHA512 of string

val verify_checksum : csum_t -> string -> unit
(** Verify the checksum of the file. *)

val verify_checksums : csum_t list -> string -> unit
(** Verify all the checksums of the file. *)

val string_of_csum_t : csum_t -> string
(** Return a string representation of the checksum type. *)

val string_of_csum : csum_t -> string
(** Return a string representation of the checksum value. *)
