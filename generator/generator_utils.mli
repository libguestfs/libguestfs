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

(** Useful utility functions. *)

val errcode_of_ret : Generator_types.ret -> Generator_types.errcode
(** Map [ret] type to the error indication that the action returns,
    eg. [errcode_of_ret RErr] => [`ErrorIsMinusOne] (meaning that
    these actions return [-1]).

    Note that [RConstOptString] cannot return an error indication, and
    this returns [`CannotReturnError].  Callers must deal with it. *)

val string_of_errcode : [`ErrorIsMinusOne|`ErrorIsNULL] -> string
(** Return errcode as a string.  Untyped for [`CannotReturnError]. *)

val uuidgen : unit -> string
(** Generate a random UUID (used in tests). *)

type rstructs_used_t = RStructOnly | RStructListOnly | RStructAndList
(** Return type of {!rstructs_used_by}. *)

val rstructs_used_by : Generator_types.action list -> (string * rstructs_used_t) list
(** Returns a list of RStruct/RStructList structs that are returned
    by any function. *)

val failwithf : ('a, unit, string, 'b) format4 -> 'a
(** Like [failwith] but supports printf-like arguments. *)

val unique : unit -> int
(** Returns a unique number each time called. *)

val replace_char : string -> char -> char -> string
(** Replace character in string. *)

val isspace : char -> bool
(** Return true if char is a whitespace character. *)

val triml : ?test:(char -> bool) -> string -> string
(** Trim left. *)

val trimr : ?test:(char -> bool) -> string -> string
(** Trim right. *)

val trim : ?test:(char -> bool) -> string -> string
(** Trim left and right. *)

val find : string -> string -> int
(** [find str sub] searches for [sub] in [str], returning the index
    or -1 if not found. *)

val replace_str : string -> string -> string -> string
(** [replace_str str s1 s2] replaces [s1] with [s2] throughout [str]. *)

val string_split : string -> string -> string list
(** [string_split sep str] splits [str] at [sep]. *)

val files_equal : string -> string -> bool
(** [files_equal filename1 filename2] returns true if the files contain
    the same content. *)

val filter_map : ('a -> 'b option) -> 'a list -> 'b list

val find_map : ('a -> 'b option) -> 'a list -> 'b

val iteri : (int -> 'a -> unit) -> 'a list -> unit

val mapi : (int -> 'a -> 'b) -> 'a list -> 'b list

val count_chars : char -> string -> int
(** Count number of times the character occurs in string. *)

val explode : string -> char list
(** Explode a string into a list of characters. *)

val map_chars : (char -> 'a) -> string -> 'a list
(** Explode string, then map function over the characters. *)

val name_of_argt : Generator_types.argt -> string
(** Extract argument name. *)

val name_of_optargt : Generator_types.optargt -> string
(** Extract optional argument name. *)

val seq_of_test : Generator_types.test -> Generator_types.seq
(** Extract test sequence from a test. *)

val c_quote : string -> string
(** Perform quoting on a string so it is safe to include in a C source file. *)

val pod2text : ?width:int -> ?trim:bool -> ?discard:bool -> string -> string -> string list
  (** [pod2text ?width ?trim ?discard name longdesc] converts the POD in
      [longdesc] to plain ASCII lines of text.

      [width] is the width in characters.  If not specified, then
      use the pod2text default.

      [trim] means trim the left margin (useful when including the
      output inside comments, as in Java generator).

      [discard] means discard the first heading.

      This is the slowest part of autogeneration, so the results are
      memoized into a temporary file. *)

val action_compare : Generator_types.action -> Generator_types.action -> int
  (** Compare the names of two actions, for sorting. *)

val chars : char -> int -> string
(** [chars c n] creates a string containing character c repeated n times. *)

val spaces : int -> string
(** [spaces n] creates a string of n spaces. *)

val args_of_optargs : Generator_types.optargs -> Generator_types.args
(** Convert a list of optargs into an equivalent list of args *)
