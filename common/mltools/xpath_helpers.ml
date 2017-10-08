(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext

(* Parse an xpath expression and return a string/int.  Returns
 * [Some v], or [None] if the expression doesn't match.
 *)
let xpath_eval parsefn xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  if Xml.xpathobj_nr_nodes obj < 1 then None
  else (
    let node = Xml.xpathobj_node obj 0 in
    let str = Xml.node_as_string node in
    try Some (parsefn str)
    with Failure _ ->
      error (f_"expecting XML expression to return an integer (expression: %s, matching string: %s)")
            expr str
  )

let xpath_string = xpath_eval identity
let xpath_int = xpath_eval int_of_string
let xpath_int64 = xpath_eval Int64.of_string

let xpath_get_nodes xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  let nodes = ref [] in
  for i = 0 to Xml.xpathobj_nr_nodes obj - 1 do
    let node = Xml.xpathobj_node obj i in
    List.push_front node nodes
  done;
  List.rev !nodes
