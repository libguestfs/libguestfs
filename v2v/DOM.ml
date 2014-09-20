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

(* Poor man's XML DOM, mutable for ease of modification. *)

open Common_utils
open Utils

open Printf

type node =
  | PCData of string
  | Comment of string
  | Element of element
and element = {
  e_name : string;                      (* Name of element. *)
  mutable e_attrs : attr list;          (* Attributes. *)
  mutable e_children : node list;       (* Child elements. *)
}
and attr = string * string
and doc = element

let doc name attrs children =
  { e_name = name; e_attrs = attrs; e_children = children }

let e name attrs children =
  Element { e_name = name; e_attrs = attrs; e_children = children }

(* This outputs nicely formatted and indented XML, ie. with lots of
 * whitespace.  As far as I know this is safe for the kind of documents
 * we will be writing, ie. libvirt XML and OVF metadata, where
 * whitespace is generally not significant, but readability is useful.
 *)
let rec node_to_chan ?(indent = 0) chan = function
  | PCData str -> output_string chan (xml_quote_pcdata str)
  | Comment str -> output_spaces chan indent; fprintf chan "<!-- %s -->" str
  | Element e -> element_to_chan ~indent chan e
and element_to_chan ?(indent = 0) chan
    { e_name = name; e_attrs = attrs; e_children = children } =
  output_spaces chan indent;
  fprintf chan "<%s" name;
  List.iter (fun (n, v) -> fprintf chan " %s='%s'" n (xml_quote_attr v)) attrs;
  if children <> [] then (
    output_string chan ">";
    let last_child_was_element = ref false in
    List.iter (
      function
      | Element _ as child ->
        last_child_was_element := true;
        output_char chan '\n';
        node_to_chan ~indent:(indent+2) chan child;
      | PCData _ as child ->
        last_child_was_element := false;
        node_to_chan ~indent:(indent+2) chan child;
      | Comment _ as child ->
        last_child_was_element := true;
        output_char chan '\n';
        node_to_chan ~indent:(indent+2) chan child;
    ) children;
    if !last_child_was_element then (
      output_char chan '\n';
      output_spaces chan indent
    );
    fprintf chan "</%s>" name
  ) else (
    output_string chan "/>"
  )

let doc_to_chan chan doc =
  fprintf chan "<?xml version='1.0' encoding='utf-8'?>\n";
  element_to_chan chan doc;
  fprintf chan "\n"

let path_to_nodes doc path =
  match path with
  | [] -> invalid_arg "path_to_nodes: empty path"
  | top_name :: path ->
    if doc.e_name <> top_name then []
    else (
      let rec loop nodes path =
        match path with
        | [] -> []
        | [p] ->
          List.filter (
            function
            | PCData _ -> false
            | Comment _ -> false
            | Element e when e.e_name = p -> true
            | Element _ -> false
          ) nodes
        | p :: ps ->
          let children =
            filter_map (
              function
              | PCData _ -> None
              | Comment _ -> None
              | Element e when e.e_name = p -> Some e.e_children
              | Element _ -> None
            ) nodes in
          List.concat (List.map (fun nodes -> loop nodes ps) children)
      in
      loop doc.e_children path
    )

let filter_node_list_by_attr nodes attr =
  List.filter (
    function
    | Element { e_attrs = attrs } when List.mem attr attrs -> true
    | Element _ | PCData _ | Comment _ -> false
  ) nodes

let find_node_by_attr nodes attr =
  match filter_node_list_by_attr nodes attr with
  | [] -> raise Not_found
  | x::_ -> x
