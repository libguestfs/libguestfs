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

(** Mini interface to libxml2. *)

type doc
(** http://xmlsoft.org/html/libxml-tree.html#xmlDocPtr *)
type node
(** http://xmlsoft.org/html/libxml-tree.html#xmlNodePtr *)
type xpathctx
(** http://xmlsoft.org/html/libxml-xpath.html#xmlXPathContextPtr *)
type xpathobj
(** http://xmlsoft.org/html/libxml-xpath.html#xmlXPathObjectPtr *)

val parse_memory : string -> doc
(** http://xmlsoft.org/html/libxml-parser.html#xmlParseMemory

    For security reasons it actually calls xmlReadMemory with the
    [XML_PARSE_NONET] option set. *)

val parse_file : string -> doc
(** [parse_file path] parses the file pointed by [path].*)

val copy_doc : doc -> recursive:bool -> doc
(** http://xmlsoft.org/html/libxml-tree.html#xmlCopyDoc *)

val to_string : doc -> format:bool -> string
(** http://xmlsoft.org/html/libxml-tree.html#xmlDocDumpFormatMemory *)

val xpath_new_context : doc -> xpathctx
(** http://xmlsoft.org/html/libxml-xpath.html#xmlXPathNewContext *)
val xpath_eval_expression : xpathctx -> string -> xpathobj
(** http://xmlsoft.org/html/libxml-xpath.html#xmlXPathEvalExpression *)
val xpath_register_ns : xpathctx -> string -> string -> unit
(** http://xmlsoft.org/html/libxml-xpathInternals.html#xmlXPathRegisterNs *)

val xpathobj_nr_nodes : xpathobj -> int
(** Get the number of nodes in the nodeset of the xmlXPathObjectPtr. *)
val xpathobj_node : xpathobj -> int -> node
(** Get the i'th node in the nodeset of the xmlXPathObjectPtr. *)

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

val node_set_content : node -> string -> unit
(** http://xmlsoft.org/html/libxml-tree.html#xmlNodeSetContent *)

val new_text_child : node -> string -> string -> node
(** http://xmlsoft.org/html/libxml-tree.html#xmlNewTextChild *)

val set_prop : node -> string -> string -> unit
(** http://xmlsoft.org/html/libxml-tree.html#xmlSetProp *)

val unset_prop : node -> string -> bool
(** http://xmlsoft.org/html/libxml-tree.html#xmlUnsetProp
    Returns [true] if the property was removed. *)

val unlink_node : node -> unit
(** http://xmlsoft.org/html/libxml-tree.html#xmlUnlinkNode
    {b NB:} This frees the [node], do not use it afterwards. *)

val doc_get_root_element : doc -> node option
(** http://xmlsoft.org/html/libxml-tree.html#xmlDocGetRootElement *)

type uri = {
  uri_scheme : string option;
  uri_opaque : string option;
  uri_authority : string option;
  uri_server : string option;
  uri_user : string option;
  uri_port : int;
  uri_path : string option;
  uri_fragment : string option;
  uri_query_raw : string option;
}

val parse_uri : string -> uri
(** http://xmlsoft.org/html/libxml-uri.html#xmlParseURI

    Parse URI.

    Note this is different from the {!URI} module which is specialized
    for parsing the [-a] parameter on the command line.  This function
    exposes the full [xmlParseURI] interface. *)
