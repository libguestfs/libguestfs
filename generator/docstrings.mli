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

type comment_style =
    CStyle | CPlusPlusStyle | HashStyle | OCamlStyle | HaskellStyle
  | ErlangStyle | LuaStyle | PODStyle
type license = GPLv2plus | LGPLv2plus

val progress_message : string

val protocol_limit_warning : string

val deprecation_notice : ?prefix:string -> ?replace_underscores:bool -> Types.action -> string option

val version_added : Types.action -> string option

val copyright_years : string

val generate_header : ?copyrights:string list -> ?inputs:string list -> ?emacs_mode:string -> comment_style -> license -> unit
