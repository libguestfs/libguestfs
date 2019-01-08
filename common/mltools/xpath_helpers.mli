(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(** XPath helper functions.

    Simple wrappers around some functions from the {!Xml} module. *)

val xpath_string : Xml.xpathctx -> string -> string option
val xpath_int : Xml.xpathctx -> string -> int option
val xpath_int64 : Xml.xpathctx -> string -> int64 option
(** Parse an xpath expression and return a string/int.  Returns
    [Some v], or [None] if the expression doesn't match. *)

val xpath_get_nodes : Xml.xpathctx -> string -> Xml.node list
(** Parse an XPath expression and return a list with the matching
    XML nodes. *)
