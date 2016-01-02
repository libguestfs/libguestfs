(* virt-sysprep
 * Copyright (C) 2012-2016 Red Hat Inc.
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

type password_crypto = [ `MD5 | `SHA256 | `SHA512 ]

val password_crypto_of_string : string -> password_crypto
(** Parse --password-crypto parameter on command line. *)

type password_selector = {
  pw_password : password;      (** The password. *)
  pw_locked : bool;            (** If the account should be locked. *)
}
and password =
| Password of string                 (** Password (literal string). *)
| Random_password                    (** Choose a random password. *)
| Disabled_password                  (** [*] in the password field. *)

val parse_selector : string -> password_selector
(** Parse the selector field in --password/--root-password.  Note this
    doesn't parse the username part.  Exits if the format is not valid. *)

type password_map = (string, password_selector) Hashtbl.t
(** A map of username -> selector. *)

val set_linux_passwords : ?password_crypto:password_crypto -> Guestfs.guestfs -> string -> password_map -> unit
(** Adjust the passwords of a Linux guest according to the
    password map. *)
