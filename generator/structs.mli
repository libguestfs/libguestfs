(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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

type cols = (string * Types.field) list
(** List of structure fields (called "columns"). *)

type struc = {
  s_name : string;                      (** Regular name. *)
  s_cols : cols;                        (** Columns. *)
  s_camel_name : string;                (** Camel-cased name. *)
  s_internal : bool;                    (** Internal only. *)
  s_unused : unit;
}

val structs : struc list
(** List of structures. *)

val lvm_pv_cols : cols
val lvm_vg_cols : cols
val lvm_lv_cols : cols
(** These are exported to the daemon code generator where they are
    used to generate code for parsing the output of commands like
    [lvs].  One day replace this with liblvm API calls. *)

val lookup_struct : string -> struc
(** Lookup a struct by name. *)

val camel_name_of_struct : string -> string
(** Lookup struct by name, return the s_camel_name field. *)

val cols_of_struct : string -> cols
(** Lookup struct by name, return the s_cols field. *)

val external_structs : struc list
(** Only external structs *)

val internal_structs : struc list
(** Only internal structs *)
