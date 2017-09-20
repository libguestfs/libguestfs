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

(* Lightweight bindings for the PCRE library. *)

exception Error of string * int

type regexp

external compile : string -> regexp = "guestfs_int_pcre_compile"
external matches : regexp -> string -> bool = "guestfs_int_pcre_matches"
external sub : int -> string = "guestfs_int_pcre_sub"
external subi : int -> int * int = "guestfs_int_pcre_subi"

let rec replace ?(global = false) patt subst subj =
  if not (matches patt subj) then
    (* Return original string unchanged if patt doesn't match. *)
    subj
  else (
    (* If patt matches "yyyy" in the original string then we have
     * the following situation, where "xxxx" is the part of the
     * original string before the match, and "zzzz..." is the
     * part after the match:
     * "xxxxyyyyzzzzzzzzzzzzz"
     *      ^   ^
     *      i1  i2
     *)
    let i1, i2 = subi 0 in
    let xs = String.sub subj 0 i1 (* "xxxx", part before the match *) in
    let zs = String.sub subj i2 (String.length subj - i2) (* after *) in

    (* If the global flag was set, we want to continue substitutions
     * in the rest of the string.
     *)
    let zs = if global then replace ~global patt subst zs else zs in

    xs ^ subst ^ zs
  )

let () =
  Callback.register_exception "PCRE.Error" (Error ("", 0))
