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
| SHA1 of string
| SHA256 of string
| SHA512 of string

type csum_result =
  | Good_checksum
  (* expected checksum, actual checksum. *)
  | Mismatched_checksum of csum_t * string
  (* referenced file does not exist *)
  | Missing_file

val of_string : string -> string -> csum_t
(** [of_string type value] returns the [csum_t] for the specified
    combination of checksum type and checksum value.

    Raise [Invalid_argument] if the checksum type is not known. *)

val verify_checksum : csum_t -> ?tar:string -> string -> csum_result
(** [verify_checksum type filename] verifies the checksum of the file.

    When optional [tar] is used it is path to uncompressed tar archive
    and the [filename] is a path in the tar archive. *)

val verify_checksums : csum_t list -> string -> csum_result
(** Verify all the checksums of the file.

    If any checksum fails, the first failure (only) is returned in
    {!csum_result}. *)

val string_of_csum_t : csum_t -> string
(** Return a string representation of the checksum type. *)

val string_of_csum : csum_t -> string
(** Return a string representation of the checksum value. *)

val compute_checksum : string -> ?tar:string -> string -> csum_t
(** [compute_checksum type filename] Computes the checksum of the file.

    The [type] is one the possible results of the [string_of_csum_t]
    function.

    When optional [tar] is used it is path to uncompressed tar archive
    and the [filename] is a path in the tar archive. *)
