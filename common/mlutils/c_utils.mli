(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** OCaml bindings for C utility functions in [common/utils]. *)

val drive_name : int -> string
val drive_index : string -> int

val shell_unquote : string -> string
(** If the string looks like a shell quoted string, then attempt to
    unquote it.

    This is just intended to deal with quoting in configuration files
    (like ones under /etc/sysconfig), and it doesn't deal with some
    situations such as $variable interpolation. *)
