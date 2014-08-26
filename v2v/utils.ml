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

(* Utilities used in virt-v2v only. *)

open Printf

open Common_gettext.Gettext
open Common_utils

open Types

let prog = Filename.basename Sys.executable_name
let error ?exit_code fs = error ~prog ?exit_code fs

let quote = Filename.quote

(* Quote XML <element attr='...'> content.  Note you must use single
 * quotes around the attribute.
 *)
let xml_quote_attr str =
  let str = replace_str str "&" "&amp;" in
  let str = replace_str str "'" "&apos;" in
  let str = replace_str str "<" "&lt;" in
  let str = replace_str str ">" "&gt;" in
  str

let xml_quote_pcdata str =
  let str = replace_str str "&" "&amp;" in
  let str = replace_str str "<" "&lt;" in
  let str = replace_str str ">" "&gt;" in
  str

(* URI quoting. *)
let uri_quote str =
  let len = String.length str in
  let xs = ref [] in
  for i = 0 to len-1 do
    xs :=
      (match str.[i] with
      | ('A'..'Z' | 'a'..'z' | '0'..'9' | '/' | '.' | '-') as c ->
        String.make 1 c
      | c ->
        sprintf "%%%02x" (Char.code c)
      ) :: !xs
  done;
  String.concat "" (List.rev !xs)

(* JSON quoting. *)
let json_quote str =
  let str = replace_str str "\\" "\\\\" in
  let str = replace_str str "\"" "\\\"" in
  let str = replace_str str "'" "\\'" in
  let str = replace_str str "\008" "\\b" in
  let str = replace_str str "\012" "\\f" in
  let str = replace_str str "\n" "\\n" in
  let str = replace_str str "\r" "\\r" in
  let str = replace_str str "\t" "\\t" in
  let str = replace_str str "\011" "\\v" in
  str

external drive_name : int -> string = "v2v_utils_drive_name"

let compare_app2_versions app1 app2 =
  let i = compare app1.Guestfs.app2_epoch app2.Guestfs.app2_epoch in
  if i <> 0 then i
  else (
    let i =
      compare_version app1.Guestfs.app2_version app2.Guestfs.app2_version in
    if i <> 0 then i
    else
      compare_version app1.Guestfs.app2_release app2.Guestfs.app2_release
  )

and compare_app2_version_min app1 (min_epoch, min_version, min_release) =
  let i = compare app1.Guestfs.app2_epoch min_epoch in
  if i <> 0 then i
  else (
    let i = compare_version app1.Guestfs.app2_version min_version in
    if i <> 0 then i
    else
      compare_version app1.Guestfs.app2_release min_release
  )

let remove_duplicates xs =
  let h = Hashtbl.create (List.length xs) in
  let rec loop = function
    | [] -> []
    | x :: xs when Hashtbl.mem h x -> xs
    | x :: xs -> Hashtbl.add h x true; x :: loop xs
  in
  loop xs
