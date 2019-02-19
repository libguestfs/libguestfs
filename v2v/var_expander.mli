(* virt-v2v
 * Copyright (C) 2019 Red Hat Inc.
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

(** Simple variable expander.

    This module provides the support to expand variables in strings,
    specified in the form of [%{name}].

    For example:

{v
let str = "variable-%{INDEX} in %{INDEX} replaced %{INDEX} times"
let index = ref 0
let fn = function
  | "INDEX" ->
    incr index;
    Some (string_of_int !index)
  | _ -> None
in
let str = Var_expander.replace_fn str fn
(* now str is "variable-1 in 2 replaced 3 times" *)
v}

    The names of variables can contain only ASCII letters (uppercase,
    and lowercase), digits, underscores, and dashes.

    The replacement is done in a single pass: this means that if a
    variable is replaced with the text of a variable, that new text
    is kept as is in the final output.  In practice:

{v
let str = "%{VAR}"
let str = Var_expander.replace_list str [("VAR", "%{VAR}")]
(* now str is "%{VAR}" *)
v}
*)

exception Invalid_variable of string
(** Invalid variable name error.

    In case a variable contains characters not allowed, then this
    exception with the actual unacceptable variable. *)

val scan_variables : string -> string list
(** Scan the pattern string for all the variables available.

    This can raise {!Invalid_variable} in case there are invalid
    variable names. *)

val replace_fn : string -> (string -> string option) -> string
(** Replaces a string expanding all the variables.

    The replacement function specify how a variable is replaced;
    if [None] is returned, then that variable is not replaced.

    This can raise {!Invalid_variable} in case there are invalid
    variable names. *)

val replace_list : string -> (string * string) list -> string
(** Replaces a string expanding all the variables.

    The replacement list specify how a variable is replaced;
    if it is not specified in the list, then that variable is not
    replaced.

    This can raise {!Invalid_variable} in case there are invalid
    variable names. *)
