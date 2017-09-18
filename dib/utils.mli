(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

val unit_GB : int -> int64
(** [unit_GB n] returns n * 2^30 *)

val current_arch : unit -> string
(** Turn the host_cpu into the dpkg architecture naming. *)

val output_filename : string -> string -> string
(** [output_filename image_name format] generates a suitable output
    filename based on the image filename and output format. *)

val log_filename : unit -> string
(** Generate a name for the log file containing the program name and
    current date/time. *)

val var_from_lines : string -> string list -> string
(** Find variable definition in a set of lines of the form [var=value]. *)

val string_index_fn : (char -> bool) -> string -> int
(** Apply function to each character in the string.  If the function
    returns true, return the index of the character.

    In other words, like {!String.index} but using a function
    instead of a single character.

    @raise Not_found if no match *)

val digit_prefix_compare : string -> string -> int

val do_mkdir : string -> unit
(** Wrapper around [mkdir -p -m 0755] *)

val get_required_tool : string -> string
(** Ensure external program is installed.  Return the full path of the
    program or fail with an error message. *)

val require_tool : string -> unit
(** Same as {!get_required_tool} but only checks the external program
    is installed and does not return the path. *)

val do_cp : string -> string -> unit
(** Wrapper around [cp -a src destdir]. *)

val ensure_trailing_newline : string -> string
(** If the input string is not [""], ensure there is a trailing ['\n'],
    adding one if necessary. *)

val not_in_list : 'a list -> 'a -> bool
(** Opposite of {!List.mem}. *)
