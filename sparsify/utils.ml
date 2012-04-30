(* virt-sparsify
 * Copyright (C) 2010-2012 Red Hat Inc.
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

(* XXX This was copied from virt-resize, and probably some of the
   functions here are not used in virt-sparsify and could be
   deleted. *)

open Printf

open Sparsify_gettext.Gettext

module G = Guestfs

let (//) = Filename.concat

let ( +^ ) = Int64.add
let ( -^ ) = Int64.sub
let ( *^ ) = Int64.mul
let ( /^ ) = Int64.div
let ( &^ ) = Int64.logand
let ( ~^ ) = Int64.lognot

let output_spaces chan n = for i = 0 to n-1 do output_char chan ' ' done

let wrap ?(chan = stdout) ?(hanging = 0) str =
  let rec _wrap col str =
    let n = String.length str in
    let i = try String.index str ' ' with Not_found -> n in
    let col =
      if col+i >= 72 then (
        output_char chan '\n';
        output_spaces chan hanging;
        i+hanging+1
      ) else col+i+1 in
    output_string chan (String.sub str 0 i);
    if i < n then (
      output_char chan ' ';
      _wrap col (String.sub str (i+1) (n-(i+1)))
    )
  in
  _wrap 0 str

let string_prefix str prefix =
  let n = String.length prefix in
  String.length str >= n && String.sub str 0 n = prefix

let rec string_find s sub =
  let len = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i <= len-sublen then (
      let rec loop2 j =
        if j < sublen then (
          if s.[i+j] = sub.[j] then loop2 (j+1)
          else -1
        ) else
          i (* found *)
      in
      let r = loop2 0 in
      if r = -1 then loop (i+1) else r
    ) else
      -1 (* not found *)
  in
  loop 0

let rec replace_str s s1 s2 =
  let len = String.length s in
  let sublen = String.length s1 in
  let i = string_find s s1 in
  if i = -1 then s
  else (
    let s' = String.sub s 0 i in
    let s'' = String.sub s (i+sublen) (len-i-sublen) in
    s' ^ s2 ^ replace_str s'' s1 s2
  )
let string_random8 =
  let chars = "abcdefghijklmnopqrstuvwxyz0123456789" in
  fun () ->
    String.concat "" (
      List.map (
        fun _ ->
          let c = Random.int 36 in
          let c = chars.[c] in
          String.make 1 c
      ) [1;2;3;4;5;6;7;8]
    )

let error fs =
  let display str =
    wrap ~chan:stderr ("virt-sparsify: error: " ^ str);
    prerr_newline ();
    prerr_newline ();
    wrap ~chan:stderr
      (s_"If reporting bugs, run virt-sparsify with the '-v' and '-x' options and include the complete output.");
    prerr_newline ();
    exit 1
  in
  ksprintf display fs

(* The reverse of device name translation, see
 * BLOCK DEVICE NAMING in guestfs(3).
 *)
let canonicalize dev =
  if String.length dev >= 8 &&
    dev.[0] = '/' && dev.[1] = 'd' && dev.[2] = 'e' && dev.[3] = 'v' &&
    dev.[4] = '/' && (dev.[5] = 'h' || dev.[5] = 'v') && dev.[6] = 'd' then (
      let dev = String.copy dev in
      dev.[5] <- 's';
      dev
    )
  else
    dev

let feature_available (g : Guestfs.guestfs) names =
  try g#available names; true
  with G.Error _ -> false

let human_size i =
  let sign, i = if i < 0L then "-", Int64.neg i else "", i in

  if i < 1024L then
    sprintf "%s%Ld" sign i
  else (
    let f = Int64.to_float i /. 1024. in
    let i = i /^ 1024L in
    if i < 1024L then
      sprintf "%s%.1fK" sign f
    else (
      let f = Int64.to_float i /. 1024. in
      let i = i /^ 1024L in
      if i < 1024L then
        sprintf "%s%.1fM" sign f
      else (
        let f = Int64.to_float i /. 1024. in
        (*let i = i /^ 1024L in*)
        sprintf "%s%.1fG" sign f
      )
    )
  )
