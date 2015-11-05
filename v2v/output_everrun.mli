(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

(** [-o everrunft] target. *)
(** [-o everrunha] target. *)

val output_everrun : string -> string -> Types.output
(** [output_everrun storage availability] creates and returns a new
    {!Types.output} object specialized for writing output to local
    files. *)

val parse_config_file : string -> string -> Types.p2v_config

val create_volumes : Types.p2v_config -> Types.everrun_volume list

val generate_volumes_xml : Types.everrun_volume list -> string

val create_guest : string -> int -> int64 -> string -> Types.p2v_config -> Types.everrun_volume list -> unit
