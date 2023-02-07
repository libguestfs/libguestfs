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

(** Useful utility functions. *)

val errcode_of_ret : Types.ret -> Types.errcode
(** Map [ret] type to the error indication that the action returns,
    eg. [errcode_of_ret RErr] => [`ErrorIsMinusOne] (meaning that
    these actions return [-1]).

    Note that [RConstOptString] cannot return an error indication, and
    this returns [`CannotReturnError].  Callers must deal with it. *)

val string_of_errcode : [`ErrorIsMinusOne|`ErrorIsNULL] -> string
(** Return errcode as a string.  Untyped for [`CannotReturnError]. *)

val stable_uuid : string
(** A random but stable UUID (used in tests). *)

type rstructs_used_t = RStructOnly | RStructListOnly | RStructAndList
(** Return type of {!rstructs_used_by}. *)

val rstructs_used_by : Types.action list -> (string * rstructs_used_t) list
(** Returns a list of RStruct/RStructList structs that are returned
    by any function. *)

val files_equal : string -> string -> bool
(** [files_equal filename1 filename2] returns true if the files contain
    the same content. *)

val name_of_argt : Types.argt -> string
(** Extract argument name. *)

val name_of_optargt : Types.optargt -> string
(** Extract optional argument name. *)

val seq_of_test : Types.c_api_test -> Types.seq
(** Extract test sequence from a test. *)

val c_quote : string -> string
(** Perform quoting on a string so it is safe to include in a C source file. *)

val html_escape : string -> string
(** Escape a text for HTML display. *)

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

val action_compare : Types.action -> Types.action -> int
  (** Compare the names of two actions, for sorting. *)

val args_of_optargs : Types.optargs -> Types.args
(** Convert a list of optargs into an equivalent list of args *)
