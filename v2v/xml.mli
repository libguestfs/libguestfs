(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** Mini interface to libxml2 for parsing libvirt XML. *)

type doc                                (** xmlDocPtr *)
type node                               (** xmlNodePtr *)
type xpathctx                           (** xmlXPathContextPtr *)
type xpathobj                           (** xmlXPathObjectPtr *)

val parse_memory : string -> doc
(** xmlParseMemory (for security reasons it actually calls xmlReadMemory) *)
val xpath_new_context : doc -> xpathctx
(** xmlXPathNewContext *)
val xpath_eval_expression : xpathctx -> string -> xpathobj
(** xmlXPathEvalExpression *)

val xpathobj_nr_nodes : xpathobj -> int
(** Get the number of nodes in the node set of the xmlXPathObjectPtr. *)
val xpathobj_node : doc -> xpathobj -> int -> node
(** Get the number of nodes in the node set of the xmlXPathObjectPtr. *)

val xpathctx_set_current_context : xpathctx -> node -> unit
(** Set the current context of an xmlXPathContextPtr to the node.
    Basically the same as the following C code:

    {v
    xpathctx->node = node
    v}

    It means the next expression you evaluate within this context will
    start at this node, when evaluating relative paths
    (eg. [./@attr]).
*)

val node_name : node -> string
(** Get the name of the node.  Note that only things like elements and
    attributes have names.  Other types of nodes will return an
    error. *)

val node_as_string : node -> string
(** Converter to turn a node into a string *)
