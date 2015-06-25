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

type doc = doc_ptr
and doc_ptr
type node_ptr
type xpathctx_ptr
type xpathobj_ptr

(* At the C level, various objects "own" other objects.  We have to
 * make that ownership explicit to the garbage collector, else we could
 * end up freeing an object before all the C references to it are
 * freed.
 *)
type xpathctx = doc_ptr * xpathctx_ptr
type xpathobj = xpathctx * xpathobj_ptr
type node = doc_ptr * node_ptr

external free_doc_ptr : doc_ptr -> unit = "v2v_xml_free_doc_ptr"
external free_xpathctx_ptr : xpathctx_ptr -> unit = "v2v_xml_free_xpathctx_ptr"
external free_xpathobj_ptr : xpathobj_ptr -> unit = "v2v_xml_free_xpathobj_ptr"

external _parse_memory : string -> doc_ptr = "v2v_xml_parse_memory"
let parse_memory xml =
  let doc_ptr = _parse_memory xml in
  Gc.finalise free_doc_ptr doc_ptr;
  doc_ptr

external xpath_new_context_ptr : doc_ptr -> xpathctx_ptr = "v2v_xml_xpath_new_context_ptr"
let xpath_new_context doc_ptr =
  let xpathctx_ptr = xpath_new_context_ptr doc_ptr in
  Gc.finalise free_xpathctx_ptr xpathctx_ptr;
  doc_ptr, xpathctx_ptr

external xpathctx_ptr_register_ns : xpathctx_ptr -> string -> string -> unit = "v2v_xml_xpathctx_ptr_register_ns"
let xpath_register_ns (_, xpathctx_ptr) prefix uri =
  xpathctx_ptr_register_ns xpathctx_ptr prefix uri

external xpathctx_ptr_eval_expression : xpathctx_ptr -> string -> xpathobj_ptr = "v2v_xml_xpathctx_ptr_eval_expression"
let xpath_eval_expression ((_, xpathctx_ptr) as xpathctx) expr =
  let xpathobj_ptr = xpathctx_ptr_eval_expression xpathctx_ptr expr in
  Gc.finalise free_xpathobj_ptr xpathobj_ptr;
  xpathctx, xpathobj_ptr

external xpathobj_ptr_nr_nodes : xpathobj_ptr -> int = "v2v_xml_xpathobj_ptr_nr_nodes"
let xpathobj_nr_nodes (_, xpathobj_ptr) =
  xpathobj_ptr_nr_nodes xpathobj_ptr

external xpathobj_ptr_get_node_ptr : xpathobj_ptr -> int -> node_ptr = "v2v_xml_xpathobj_ptr_get_node_ptr"
let xpathobj_node ((doc_ptr, _), xpathobj_ptr) i =
  doc_ptr, xpathobj_ptr_get_node_ptr xpathobj_ptr i

external xpathctx_ptr_set_node_ptr : xpathctx_ptr -> node_ptr -> unit = "v2v_xml_xpathctx_set_node_ptr"
let xpathctx_set_current_context (_, xpathctx_ptr) (_, node_ptr) =
  xpathctx_ptr_set_node_ptr xpathctx_ptr node_ptr

external node_ptr_name : node_ptr -> string = "v2v_xml_node_ptr_name"
let node_name (_, node_ptr) = node_ptr_name node_ptr

external node_ptr_as_string : doc_ptr -> node_ptr -> string = "v2v_xml_node_ptr_as_string"
let node_as_string (doc_ptr, node_ptr) = node_ptr_as_string doc_ptr node_ptr

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
