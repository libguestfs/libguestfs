(* Wrapper around ocaml-gettext.
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** Gettext functions for OCaml virt tools.

    The Common_gettext module provides gettext functions, or dummy
    functions if ocaml-gettext was not available at configure time.

    {b Note}: Don't translate debug strings, or strings which are
    meant to be read/written only by machine.

    There are two ways to translate constant strings in OCaml programs.

    For ordinary strings, replace ["string"] with [s_"string"].  Since
    this is a function call to a function called [s_], you may have
    to put parentheses around the expression.

    For format strings, use:

{v
  printf (f_"zeroing filesystem %s") filename;
v}

    Note for format strings, the parentheses are almost always required,
    and they just go around the [(f_"string")], {i not} around the other
    arguments of the printf function.

    At build time, a program parses the OCaml code into an abstract
    syntax tree and statically determines all calls to the special
    [s_] and [f_] functions, which means: (a) You can be very loose
    with syntax, unlike ordinary xgettext, but (b) you cannot rename
    these functions.
*)

module Gettext : sig
  val s_ : string -> string
  val f_ :
    ('a, 'b, 'c, 'c, 'c, 'd) format6 -> ('a, 'b, 'c, 'c, 'c, 'd) format6
  val sn_ : string -> string -> int -> string
  val fn_ :
    ('a, 'b, 'c, 'c, 'c, 'd) format6 ->
    ('a, 'b, 'c, 'c, 'c, 'd) format6 ->
    int -> ('a, 'b, 'c, 'c, 'c, 'd) format6
end
