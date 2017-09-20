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

let () =
  Callback.register_exception "PCRE.Error" (Error ("", 0))
