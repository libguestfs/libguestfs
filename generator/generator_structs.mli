(* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

(** Structures returned by the API. *)

type cols = (string * Generator_types.field) list
(** List of structure fields (called "columns"). *)

val structs : (string * cols) list
(** List of structures. *)

val java_structs : (string * string) list
(** Of course, Java has to be different from everyone else. *)

val lvm_pv_cols : cols
val lvm_vg_cols : cols
val lvm_lv_cols : cols
(** These are exported to the daemon code generator where they are
    used to generate code for parsing the output of commands like
    [lvs].  One day replace this with liblvm API calls. *)

val java_name_of_struct : string -> string
(** Extract Java name of struct. *)

val cols_of_struct : string -> cols
(** Extract columns of a struct. *)
