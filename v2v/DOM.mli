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

(** Poor man's XML DOM, mutable for ease of modification. *)

type node =
  | PCData of string                    (** Text. *)
  | Comment of string                   (** <!-- comment --> *)
  | Element of element                  (** <element/> with attrs and children *)
and element = {
  e_name : string;                      (** Name of element. *)
  mutable e_attrs : attr list;          (** Attributes. *)
  mutable e_children : node list;       (** Child elements. *)
}
and attr = string * string
and doc = element

val doc : string -> attr list -> node list -> doc
(** A quick way to create a document. *)

val e : string -> attr list -> node list -> node
(** A quick way to create elements. *)

val doc_to_chan : out_channel -> doc -> unit
(** Write the XML document to an output channel. *)

val path_to_nodes : doc -> string list -> node list
(** Search down the path and return a list of all matching elements.
    Returns an empty list if none were found. *)

val filter_node_list_by_attr : node list -> attr -> node list
(** Find DOM elements which have a particular attribute name=value (not
    recursively).  If not found, returns an empty list. *)

val find_node_by_attr : node list -> attr -> node
(** Find the first DOM element which has a particular attribute
    name=value (not recursively).  If not found, raises
    [Not_found]. *)
