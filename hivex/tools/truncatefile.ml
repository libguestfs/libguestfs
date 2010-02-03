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
open Visualizer_utils

let () =
  if Array.length Sys.argv <> 3 then (
    eprintf "Error: missing argument.
Usage: %s hivefile endpages
" Sys.executable_name;
    exit 1
  )

let filename = Sys.argv.(1)
let new_end_pages = int_of_string Sys.argv.(2)

(* Load the file. *)
let bits = bitstring_of_file filename

(* Split into header + data at the 4KB boundary. *)
let header, data = takebits (4096 * 8) bits, dropbits (4096 * 8) bits

(* Truncate the file data. *)
let data = takebits (new_end_pages * 8) data

(* Read the header fields. *)
let seq, last_modified, major, minor, unknown1, unknown2,
  root_key, end_pages,  unknown3, fname =
  bitmatch header with
  | { "regf" : 4*8 : string;
      seq1 : 4*8 : littleendian;
      seq2 : 4*8 : littleendian;
      last_modified : 64 : bitstring;
      major : 4*8 : littleendian;
      minor : 4*8 : littleendian;
      unknown1 : 4*8 : littleendian;
      unknown2 : 4*8 : littleendian;
      root_key : 4*8 : littleendian;
      end_pages : 4*8 : littleendian;
      unknown3 : 4*8 : littleendian;
      fname : 64*8 : string;
      unknownguid1 : 16*8 : bitstring;
      unknownguid2 : 16*8 : bitstring;
      unknown4 : 4*8 : littleendian;
      unknownguid3 : 16*8 : bitstring;
      unknown5 : 4*8 : string;
      unknown6 : 340*8 : bitstring;
      csum : 4*8
        : littleendian, save_offset_to (crc_offset),
          check (assert (crc_offset = 0x1fc * 8); true);
      unknown7 : (0x1000-0x200)*8 : bitstring } ->
      seq1, last_modified, major, minor, unknown1, unknown2,
      root_key, end_pages, unknown3, fname
  | {_} -> assert false

(* Create a new header, with endpages updated. *)
let header =
  let zeroguid = zeroes_bitstring (16*8) in
  let before_csum =
    BITSTRING {
      "regf" : 4*8 : string;
      seq : 4*8 : littleendian;
      seq : 4*8 : littleendian;
      last_modified : 64 : bitstring;
      major : 4*8 : littleendian;
      minor : 4*8 : littleendian;
      unknown1 : 4*8 : littleendian;
      unknown2 : 4*8 : littleendian;
      root_key : 4*8 : littleendian;
      Int32.of_int new_end_pages : 4*8 : littleendian;
      unknown3 : 4*8 : littleendian;
      fname : 64*8 : string;
      zeroguid : 16*8 : bitstring;
      zeroguid : 16*8 : bitstring;
      0_l : 4*8 : littleendian;
      zeroguid : 16*8 : bitstring;
      0_l : 4*8 : littleendian;
      zeroes_bitstring (340*8) : 340*8 : bitstring
    } in
  assert (bitstring_length before_csum = 0x1fc * 8);
  let csum = bitstring_fold_left_int32_le Int32.logxor 0_l before_csum in
  let csum_and_after =
    BITSTRING {
      csum : 4*8 : littleendian;
      zeroes_bitstring ((0x1000-0x200)*8) : (0x1000-0x200)*8 : bitstring
    } in
  let new_header = concat [before_csum; csum_and_after] in
  assert (bitstring_length header = bitstring_length new_header);
  new_header

(* Write it. *)
let () =
  let file = concat [header; data] in
  bitstring_to_file file filename
