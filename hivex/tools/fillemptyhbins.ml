(* Windows Registry reverse-engineering tool.
 * Copyright (C) 2010 Red Hat Inc.
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

open Bitstring
open ExtString
open Printf

let () =
  if Array.length Sys.argv <> 3 then (
    eprintf "Error: missing argument.
Usage: %s hivefile startoffset
" Sys.executable_name;
    exit 1
  )

let filename = Sys.argv.(1)
let offset = int_of_string Sys.argv.(2)

(* Load the file. *)
let bits = bitstring_of_file filename

(* Split into header + data at the 4KB boundary. *)
let header, data = takebits (4096 * 8) bits, dropbits (4096 * 8) bits

(* Overwrite everything after @offset, so ... *)
let nrpages = (bitstring_length data / 8 - offset) / 4096
let data = takebits (offset * 8) data

(* Create the empty pages.  They're not all the same because each
 * page contains its own page_offset.
 *)
let pages =
  let noblock =
    let seg_len = 4096 - 32 in
    let zeroes = zeroes_bitstring ((seg_len - 4) * 8) in
    BITSTRING {
      Int32.of_int seg_len : 4*8 : littleendian;
      zeroes : (seg_len - 4) * 8 : bitstring
    } in
  let zeroes = zeroes_bitstring (20*8) in
  let rec loop page_offset i =
    if i < nrpages then (
      let page =
        BITSTRING {
          "hbin" : 4*8 : string;
          Int32.of_int page_offset : 4*8 : littleendian;
          4096_l : 4*8 : littleendian; (* page length *)
          zeroes : 20*8 : bitstring;
          noblock : (4096 - 32) * 8 : bitstring
        } in
      page :: loop (page_offset + 4096) (i+1)
    ) else []
  in
  loop offset 0

(* Write it. *)
let () =
  let file = concat (header :: data :: pages) in
  bitstring_to_file file filename
