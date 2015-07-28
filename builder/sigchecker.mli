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

type t

val create : gpg:string -> gpgkey:Utils.gpgkey_type -> check_signature:bool -> t

val verifying_signatures : t -> bool
(** Return whether signatures are being verified by this
    Sigchecker.t. *)

val verify : t -> string -> unit
(** Verify the file is signed (if check_signature is true). *)

val verify_detached : t -> string -> string option -> unit
(** Verify the file is signed against the detached signature
    (if check_signature is true). *)

val verify_and_remove_signature : t -> string -> string option
(** If check_signature is true, verify the file is signed and extract
    the content of the file (i.e. without the signature). *)
