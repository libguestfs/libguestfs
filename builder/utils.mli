(* virt-builder
 * Copyright (C) 2013-2018 Red Hat Inc.
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

(** Utilities/common functions used in virt-builder only. *)

type gpgkey_type =
  | No_Key
  | Fingerprint of string
  | KeyFile of string
and revision =
  | Rev_int of int
  | Rev_string of string

val string_of_revision : revision -> string
(** Convert a {!revision} into a string. *)

val get_image_infos : string -> JSON_parser.json_parser_val
(** [get_image_infos path] Run qemu-img info on the image pointed at
    path as JSON tree. *)

val increment_revision : revision -> revision
(** Add one to the revision number *)
