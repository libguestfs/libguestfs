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

(* Mini interface to libxml2. *)

type doc
type node_ptr
type xpathctx
type xpathobj

(* Since node is owned by doc, we have to make that explicit to the
 * garbage collector.
 *)
type node = doc * node_ptr

external parse_memory : string -> doc = "v2v_xml_parse_memory"
external xpath_new_context : doc -> xpathctx = "v2v_xml_xpath_new_context"
external xpath_eval_expression : xpathctx -> string -> xpathobj = "v2v_xml_xpath_eval_expression"
external xpath_register_ns : xpathctx -> string -> string -> unit = "v2v_xml_xpath_register_ns"

external xpathobj_nr_nodes : xpathobj -> int = "v2v_xml_xpathobj_nr_nodes"
external xpathobj_get_node_ptr : xpathobj -> int -> node_ptr = "v2v_xml_xpathobj_get_node_ptr"
let xpathobj_node doc xpathobj i =
  let n = xpathobj_get_node_ptr xpathobj i in
  (doc, n)

external xpathctx_set_node_ptr : xpathctx -> node_ptr -> unit = "v2v_xml_xpathctx_set_node_ptr"
let xpathctx_set_current_context xpathctx (_, node) =
  xpathctx_set_node_ptr xpathctx node

external node_ptr_name : node_ptr -> string = "v2v_xml_node_ptr_name"
let node_name (_, node) = node_ptr_name node

external node_ptr_as_string : doc -> node_ptr -> string = "v2v_xml_node_ptr_as_string"
let node_as_string (doc, node) =
  node_ptr_as_string doc node

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

external parse_uri : string -> uri = "v2v_xml_parse_uri"
