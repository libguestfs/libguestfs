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

type node = int64
type value = int64

type t = Guestfs.guestfs * node

let with_hive_readonly (g : Guestfs.guestfs) hive_filename f =
  let verbose = verbose () in
  g#hivex_open ~write:false ~unsafe:true ~verbose (* ~debug:verbose *)
               hive_filename;
  protect
    ~f:(
      fun () ->
        let t = g, g#hivex_root () in
        f t
    )
    ~finally:g#hivex_close

let with_hive_write (g : Guestfs.guestfs) hive_filename f =
  let verbose = verbose () in
  g#hivex_open ~write:true ~verbose (* ~debug:verbose *) hive_filename;
  protect
    ~f:(
      fun () ->
        let t = g, g#hivex_root () in
        let ret = f t in
        g#hivex_commit None;
        ret
    )
    ~finally:g#hivex_close

(* Find the given node in the current hive, relative to the starting
 * point.  Returns [None] if the node is not found.
 *)
let rec get_node ((g, node) : t) = function
  | [] -> Some node
  | x :: xs ->
     let node = g#hivex_node_get_child node x in
     if node = 0L then None
     else get_node (g, node) xs

let rec create_path ((g, parent) : t) = function
  | [] -> parent
  | x :: xs ->
     let node =
       match g#hivex_node_get_child parent x with
       | 0L -> g#hivex_node_add_child parent x (* not found, create *)
       | node -> node in
     create_path (g, node) xs

(* Take a 7 bit ASCII string and encode it as UTF16LE. *)
let encode_utf16le str =
  let len = String.length str in
  let copy = Bytes.make (len*2) '\000' in
  for i = 0 to len-1 do
    Bytes.unsafe_set copy (i*2) (String.unsafe_get str i)
  done;
  Bytes.to_string copy

(* Take a UTF16LE string and decode it to UTF-8.  Actually this
 * fails if the string is not 7 bit ASCII.  XXX Use iconv here.
 *)
let decode_utf16le str =
  let len = String.length str in
  if len mod 2 <> 0 then
    error (f_"decode_utf16le: Windows string does not appear to be in UTF16-LE encoding.  This could be a bug in %s.") prog;
  let copy = Bytes.create (len/2) in
  for i = 0 to (len/2)-1 do
    let cl = String.unsafe_get str (i*2) in
    let ch = String.unsafe_get str ((i*2)+1) in
    if ch != '\000' || Char.code cl >= 127 then
      error (f_"decode_utf16le: Windows UTF16-LE string contains non-7-bit characters.  This is a bug in %s, please report it.") prog;
    Bytes.unsafe_set copy i cl
  done;
  Bytes.to_string copy
