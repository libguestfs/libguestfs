(* Bindings for libxml2
 * Copyright (C) 2009-2018 Red Hat Inc.
 * Copyright (C) 2017 SUSE Inc.
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

(* At the C level, various objects "own" other objects.  For
 * example, 'xmlNodePtr's live in 'xmlDocPtr's.  We have to
 * make that ownership explicit to the garbage collector, else
 * we could end up freeing an object before all the C references
 * to it are freed.
 *
 * In this file, any type called '*ptr' refers to the OCaml
 * representation of a C 'xml*Ptr'.  Other types refer to the
 * tuple where we group the underlying C pointer with the owning
 * object to avoid the GC problem mentioned above.  So for example,
 *
 *   type nodeptr                ... is the xmlNodePtr
 *   type node = doc * nodeptr   ... is the public GC-safe tuple type
 *
 * For 'doc' and 'docptr', these have the same type since there
 * is no need for the wrapper.
 *
 * To ensure that finalization happens in the correct order, we
 * must use the OCaml-level Gc.finalise function instead of the C
 * custom operations finalizer.
 *
 * Also note that xmlNodePtr does not need to be finalized, since
 * they are allocated inside the xmlDocPtr object.
 *
 * See also this commit message:
 * https://github.com/libguestfs/libguestfs/commit/3888582da89c757d0740d11c3a62433d748c85aa
 *)

type docptr
type nodeptr
type xpathctxptr
type xpathobjptr

type doc = docptr
type node = doc * nodeptr
type xpathctx = doc * xpathctxptr
type xpathobj = xpathctx * xpathobjptr

external free_docptr : docptr -> unit = "mllib_xml_free_docptr"
external free_xpathctxptr : xpathctxptr -> unit = "mllib_xml_free_xpathctxptr"
external free_xpathobjptr : xpathobjptr -> unit = "mllib_xml_free_xpathobjptr"

external _parse_memory : string -> docptr = "mllib_xml_parse_memory"
let parse_memory xml =
  let docptr = _parse_memory xml in
  Gc.finalise free_docptr docptr;
  docptr

external _parse_file : string -> docptr = "mllib_xml_parse_file"
let parse_file filename =
  let docptr = _parse_file filename in
  Gc.finalise free_docptr docptr;
  docptr

external _copy_doc : docptr -> recursive:bool -> docptr = "mllib_xml_copy_doc"
let copy_doc docptr ~recursive =
  let copy = _copy_doc docptr ~recursive in
  Gc.finalise free_docptr copy;
  copy

external to_string : docptr -> format:bool -> string = "mllib_xml_to_string"

external _xpath_new_context : docptr -> xpathctxptr
  = "mllib_xml_xpath_new_context"
let xpath_new_context docptr =
  let xpathctxptr = _xpath_new_context docptr in
  Gc.finalise free_xpathctxptr xpathctxptr;
  docptr, xpathctxptr

external xpathctxptr_register_ns : xpathctxptr -> string -> string -> unit
  = "mllib_xml_xpathctxptr_register_ns"
let xpath_register_ns (_, xpathctxptr) prefix uri =
  xpathctxptr_register_ns xpathctxptr prefix uri

external xpathctxptr_eval_expression : xpathctxptr -> string -> xpathobjptr
  = "mllib_xml_xpathctxptr_eval_expression"
let xpath_eval_expression ((_, xpathctxptr) as xpathctx) expr =
  let xpathobjptr = xpathctxptr_eval_expression xpathctxptr expr in
  Gc.finalise free_xpathobjptr xpathobjptr;
  xpathctx, xpathobjptr

external xpathobjptr_nr_nodes : xpathobjptr -> int
  = "mllib_xml_xpathobjptr_nr_nodes"
let xpathobj_nr_nodes (_, xpathobjptr) =
  xpathobjptr_nr_nodes xpathobjptr

external xpathobjptr_get_nodeptr : xpathobjptr -> int -> nodeptr
  = "mllib_xml_xpathobjptr_get_nodeptr"
let xpathobj_node ((docptr, _), xpathobjptr) i =
  docptr, xpathobjptr_get_nodeptr xpathobjptr i

external xpathctxptr_set_nodeptr : xpathctxptr -> nodeptr -> unit
  = "mllib_xml_xpathctx_set_nodeptr"
let xpathctx_set_current_context (_, xpathctxptr) (_, nodeptr) =
  xpathctxptr_set_nodeptr xpathctxptr nodeptr

external nodeptr_name : nodeptr -> string = "mllib_xml_nodeptr_name"
let node_name (_, nodeptr) = nodeptr_name nodeptr

external nodeptr_as_string : docptr -> nodeptr -> string
  = "mllib_xml_nodeptr_as_string"
let node_as_string (docptr, nodeptr) = nodeptr_as_string docptr nodeptr

external nodeptr_set_content : nodeptr -> string -> unit
  = "mllib_xml_nodeptr_set_content"
let node_set_content (_, nodeptr) = nodeptr_set_content nodeptr

external nodeptr_new_text_child : nodeptr -> string -> string -> nodeptr
  = "mllib_xml_nodeptr_new_text_child"
let new_text_child (docptr, nodeptr) name content =
  docptr, nodeptr_new_text_child nodeptr name content

external nodeptr_set_prop : nodeptr -> string -> string -> unit
  = "mllib_xml_nodeptr_set_prop"
let set_prop (_, nodeptr) = nodeptr_set_prop nodeptr

external nodeptr_unset_prop : nodeptr -> string -> bool
  = "mllib_xml_nodeptr_unset_prop"
let unset_prop (_, nodeptr) = nodeptr_unset_prop nodeptr

external nodeptr_unlink_node : nodeptr -> unit = "mllib_xml_nodeptr_unlink_node"
let unlink_node (_, nodeptr) = nodeptr_unlink_node nodeptr

external _doc_get_root_element : docptr -> nodeptr option
  = "mllib_xml_doc_get_root_element"
let doc_get_root_element docptr =
  match _doc_get_root_element docptr with
  | None -> None
  | Some nodeptr -> Some (docptr, nodeptr)

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

external parse_uri : string -> uri = "mllib_xml_parse_uri"
