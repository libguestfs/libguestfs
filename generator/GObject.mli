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

val generate_gobject_header : unit -> unit
val generate_gobject_makefile : unit -> unit
val generate_gobject_optargs_header : string -> string -> Types.action -> unit -> unit
val generate_gobject_optargs_source : string -> string -> Types.optargt list -> Types.action -> unit -> unit
val generate_gobject_session_header : unit -> unit
val generate_gobject_session_source : unit -> unit
val generate_gobject_struct_header : string -> string -> (string * Types.field) list -> unit -> unit
val generate_gobject_struct_source : string -> string -> unit -> unit
val generate_gobject_tristate_header : unit -> unit
val generate_gobject_tristate_source : unit -> unit
