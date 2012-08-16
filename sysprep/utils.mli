(* virt-sysprep
 * Copyright (C) 2010-2012 Red Hat Inc.
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

(** Utility functions. *)

val (//) : string -> string -> string
(** Filename concatenation. *)

val failwithf : ('a, unit, string, 'b) format4 -> 'a
(** Like [failwith] but supports printf-like arguments. *)

val string_prefix : string -> string -> bool
(** [string_prefix str prefix] returns true iff [prefix] is a prefix
    of [str]. *)

val string_find : string -> string -> int
(** [string_find str sub] finds [sub] in [str].  It returns the index
    (position) in the string, or [-1] if not found. *)

val string_split : string -> string -> string list
(** [string_split sep str] splits [str] at [sep] (maybe multiple
    times), returning a list of strings. *)

val string_random8 : unit -> string
(** Return a random 8 character string, suitable as a temporary
    filename since every filesystem supports at least 8 character
    filenames. *)

val skip_dashes : string -> string
(** Take a string like ["--str"] and return ["str"], that is, skip
    any leading dash characters.

    If the string contains only dash characters, this raises
    [Invalid_argument "skip_dashes"]. *)

val compare_command_line_args : string -> string -> int
(** Compare two command line arguments (eg. ["-a"] and ["--V"]),
    ignoring leading dashes and case.  Note this assumes the
    strings are 7 bit ASCII. *)
