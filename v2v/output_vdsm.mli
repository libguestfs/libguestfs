(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

(** [-o vdsm] target. *)

type vdsm_options
(** Miscellaneous extra command line parameters used by VDSM. *)

val print_output_options : unit -> unit
val parse_output_options : (string * string) list -> vdsm_options
(** Print and parse vdsm -oo options. *)

val output_vdsm : string -> vdsm_options -> Types.output_allocation -> Types.output
(** [output_vdsm os vdsm_options output_alloc] creates and
    returns a new {!Types.output} object specialized for writing
    output to Data Domains directly under VDSM control. *)
