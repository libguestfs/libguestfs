(* virt-customize
 * Copyright (C) 2014 Red Hat Inc.
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

type ssh_key_selector =
| SystemKey                    (* Default key from the user in the system, in
                                * the style of ssh-copy-id(1)/default_ID_file.
                                *)
| KeyFile of string            (* Key from the specified file. *)
| KeyString of string          (* Key specified as string. *)

val parse_selector : string -> ssh_key_selector
(** Parse the selector field in --ssh-inject.  Note this
    doesn't parse the username part.  Exits if the format is not valid. *)

val do_ssh_inject_unix : Guestfs.guestfs -> string -> ssh_key_selector -> unit
(** Inject on a generic Unix system (Linux, FreeBSD, etc) the ssh key
    for the specified user. *)
