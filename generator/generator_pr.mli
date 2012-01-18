(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

(** Printing and current output file. *)

val pr : ('a, unit, string, unit) format4 -> 'a
(** General printing function which prints to the current output file. *)

val output_to : string -> (unit -> unit) -> unit
(** [output_to filename f] runs [f] and writes the result to [filename].
    [filename] is only updated if the output is different from what
    is in the file already. *)

val get_lines_generated : unit -> int
(** Return number of lines of code generated. *)

val get_files_generated : unit -> string list
(** Return names of the files that were generated. *)
