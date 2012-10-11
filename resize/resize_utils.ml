(* virt-resize
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

open Printf

open Resize_gettext.Gettext

module G = Guestfs

let ( +^ ) = Int64.add
let ( -^ ) = Int64.sub
let ( *^ ) = Int64.mul
let ( /^ ) = Int64.div
let ( &^ ) = Int64.logand
let ( ~^ ) = Int64.lognot

let int_of_le32 str =
  assert (String.length str = 4);
  let c0 = Char.code (String.unsafe_get str 0) in
  let c1 = Char.code (String.unsafe_get str 1) in
  let c2 = Char.code (String.unsafe_get str 2) in
  let c3 = Char.code (String.unsafe_get str 3) in
  Int64.of_int c0 +^
    (Int64.shift_left (Int64.of_int c1) 8) +^
    (Int64.shift_left (Int64.of_int c2) 16) +^
    (Int64.shift_left (Int64.of_int c3) 24)

let le32_of_int i =
  let c0 = i &^ 0xffL in
  let c1 = Int64.shift_right (i &^ 0xff00L) 8 in
  let c2 = Int64.shift_right (i &^ 0xff0000L) 16 in
  let c3 = Int64.shift_right (i &^ 0xff000000L) 24 in
  let s = String.create 4 in
  String.unsafe_set s 0 (Char.unsafe_chr (Int64.to_int c0));
  String.unsafe_set s 1 (Char.unsafe_chr (Int64.to_int c1));
  String.unsafe_set s 2 (Char.unsafe_chr (Int64.to_int c2));
  String.unsafe_set s 3 (Char.unsafe_chr (Int64.to_int c3));
  s

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

let error fs =
  let display str =
    wrap ~chan:stderr (s_"virt-resize: error: " ^ str);
    prerr_newline ();
    prerr_newline ();
    wrap ~chan:stderr
      (s_"If reporting bugs, run virt-resize with the '-d' option and include the complete output.");
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

(* Parse the size field from --resize and --resize-force options. *)
let parse_size =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$"
  and plus_const_re = Str.regexp "^\\+\\([.0-9]+\\)\\([bKMG]\\)$"
  and minus_const_re = Str.regexp "^-\\([.0-9]+\\)\\([bKMG]\\)$"
  and percent_re = Str.regexp "^\\([.0-9]+\\)%$"
  and plus_percent_re = Str.regexp "^\\+\\([.0-9]+\\)%$"
  and minus_percent_re = Str.regexp "^-\\([.0-9]+\\)%$"
  in
  fun oldsize field ->
    let matches rex = Str.string_match rex field 0 in
    let sub i = Str.matched_group i field in
    let size_scaled f = function
      | "b" -> Int64.of_float f
      | "K" -> Int64.of_float (f *. 1024.)
      | "M" -> Int64.of_float (f *. 1024. *. 1024.)
      | "G" -> Int64.of_float (f *. 1024. *. 1024. *. 1024.)
      | _ -> assert false
    in

    if matches const_re then (
      size_scaled (float_of_string (sub 1)) (sub 2)
    )
    else if matches plus_const_re then (
      let incr = size_scaled (float_of_string (sub 1)) (sub 2) in
      oldsize +^ incr
    )
    else if matches minus_const_re then (
      let incr = size_scaled (float_of_string (sub 1)) (sub 2) in
      oldsize -^ incr
    )
    else if matches percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize *^ percent /^ 1000L
    )
    else if matches plus_percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize +^ oldsize *^ percent /^ 1000L
    )
    else if matches minus_percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize -^ oldsize *^ percent /^ 1000L
    )
    else
      error "virt-resize: %s: cannot parse size field" field

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
