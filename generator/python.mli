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

val generate_python_actions_h : unit -> unit
val generate_python_structs : unit -> unit
val generate_python_actions : Types.action list -> unit -> unit
val generate_python_module : unit -> unit
val generate_python_py : unit -> unit

val indent_python : string -> int -> int -> string
(** [indent_python str indent columns] indents a Python comma-based string
    like "foo, bar, etc" (with space after the comma), splitting at commas
    so each line does not take more than [columns] characters, including
    [indent].

    Lines after the first are indented with [indent] spaces. *)
