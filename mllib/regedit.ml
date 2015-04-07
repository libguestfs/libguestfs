(* virt-v2v
 * Copyright (C) 2014 Red Hat Inc.
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

open Common_utils
open Common_gettext.Gettext

type regedits = regedit list
and regedit = regkeypath * regvalues
and regkeypath = string list
and regvalues = regvalue list
and regvalue = string * regtype
and regtype =
| REG_NONE
| REG_SZ of string
| REG_EXPAND_SZ of string
| REG_BINARY of string
| REG_DWORD of int32
| REG_MULTI_SZ of string list

(* Take a 7 bit ASCII string and encode it as UTF16LE. *)
let encode_utf16le str =
  let len = String.length str in
  let copy = String.make (len*2) '\000' in
  for i = 0 to len-1 do
    String.unsafe_set copy (i*2) (String.unsafe_get str i)
  done;
  copy

(* Take a UTF16LE string and decode it to UTF-8.  Actually this
 * fails if the string is not 7 bit ASCII.  XXX Use iconv here.
 *)
let decode_utf16le ~prog str =
  let len = String.length str in
  if len mod 2 <> 0 then
    error ~prog (f_"decode_utf16le: Windows string does not appear to be in UTF16-LE encoding.  This could be a bug in %s.") prog;
  let copy = String.create (len/2) in
  for i = 0 to (len/2)-1 do
    let cl = String.unsafe_get str (i*2) in
    let ch = String.unsafe_get str ((i*2)+1) in
    if ch != '\000' || Char.code cl >= 127 then
      error ~prog (f_"decode_utf16le: Windows UTF16-LE string contains non-7-bit characters.  This is a bug in %s, please report it.") prog;
    String.unsafe_set copy i cl
  done;
  copy

let rec import_key (g : Guestfs.guestfs) root (path, values) =
  (* Create the path starting at the root node. *)
  let node =
    let rec loop parent = function
      | [] -> parent
      | x :: xs ->
        let node =
          match g#hivex_node_get_child parent x with
          | 0L -> g#hivex_node_add_child parent x (* not found, create *)
          | node -> node in
        loop node xs
    in
    loop root path in

  (* Delete any existing values in this node. *)
  (* g#hivex_node_set_values ...
     XXX Or at least, it would be nice to do this, but there is no
     binding for it in libguestfs.  I'm not sure how much this matters. *)

  (* Create the values. *)
  import_values g node values

and import_values g node = List.iter (import_value g node)

and import_value g node = function
  | key, REG_NONE -> g#hivex_node_set_value node key 0L ""
  (* All string registry fields have a terminating NUL, which in
   * UTF-16LE means they have 3 zero bytes -- the first is the high
   * byte from the last character, and the second and third are the
   * UTF-16LE encoding of ASCII NUL.  So we have to add two zero
   * bytes at the end of string fields.
   *)
  | key, REG_SZ s ->
    g#hivex_node_set_value node key 1L (encode_utf16le s ^ "\000\000")
  | key, REG_EXPAND_SZ s ->
    g#hivex_node_set_value node key 2L (encode_utf16le s ^ "\000\000")
  | key, REG_BINARY bin ->
    g#hivex_node_set_value node key 3L bin
  | key, REG_DWORD dw ->
    g#hivex_node_set_value node key 4L (le32_of_int (Int64.of_int32 dw))
  | key, REG_MULTI_SZ ss ->
    (* http://blogs.msdn.com/oldnewthing/archive/2009/10/08/9904646.aspx *)
    List.iter (fun s -> assert (s <> "")) ss;
    let ss = ss @ [""] in
    let ss = List.map (fun s -> encode_utf16le s ^ "\000\000") ss in
    let ss = String.concat "" ss in
    g#hivex_node_set_value node key 7L ss

let reg_import g root = List.iter (import_key g root)
