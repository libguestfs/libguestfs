(* virt-builder
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

val mkdtemp : string -> string
(** [mkdtemp pattern] Tiny wrapper to the C [mkdtemp]. *)

val temp_dir : ?base_dir:string -> string -> string -> string
(** [temp_dir prefix suffix] creates a new unique temporary directory.

    The optional [~base_dir:string] changes the base directory where
    to create the new temporary directory; if not specified, the default
    [Filename.temp_dir_name] is used. *)
