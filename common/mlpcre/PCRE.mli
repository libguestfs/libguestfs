(* Bindings for Perl-compatible Regular Expressions.
 * Copyright (C) 2017 Red Hat Inc.
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

(** Lightweight bindings for the PCRE library.

    Note this is {i not} Markus Mottl's ocaml-pcre, and doesn't
    work like that library.

    To match a regular expression:

{v
let re = PCRE.compile "(a+)b"
...

if PCRE.matches re "ccaaaabb" then (
  let whole = PCRE.sub 0 in (* returns "aaaab" *)
  let first = PCRE.sub 1 in (* returns "aaaa" *)
  ...
)
v}

    Note that there is implicit global state stored between the
    call to {!matches} and {!sub}.  This is stored in thread
    local storage so it is safe provided there are no other calls
    to {!matches} in the same thread.
*)

exception Error of string * int
(** PCRE error raised by various functions.

    The string is the printable error message.

    The integer is one of the negative [PCRE_*] error codes
    (see pcreapi(3) for a full list), {i or} one of the positive
    error codes from [pcre_compile2].  It may also be 0 if there
    was no error code information. *)

type regexp
(** The type of a compiled regular expression. *)

val compile : string -> regexp
(** Compile a regular expression.  This can raise {!Error}. *)

val matches : regexp -> string -> bool
(** Test whether the regular expression matches the string.  This
    returns true if the regexp matches or false otherwise.

    This also saves any matched substrings in thread-local storage
    until either the next call to {!matches} in the current thread
    or the thread/program exits.  You can call {!sub} to return
    these substrings.

    This can raise {!Error} if PCRE returns an error. *)

val sub : int -> string
(** Return the nth substring (capture) matched by the previous call
    to {!matches} in the current thread.

    If [n == 0] it returns the whole matching part of the string.

    If [n >= 1] it returns the nth substring.

    If there was no nth substring then this raises [Not_found].
    This can also raise {!Error} for other PCRE-related errors. *)
