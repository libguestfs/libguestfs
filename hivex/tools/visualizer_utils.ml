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
 *
 * For existing information on the registry format, please refer
 * to the following documents.  Note they are both incomplete
 * and inaccurate in some respects.
 *)

open ExtString
open Printf

let failwithf fs = ksprintf failwith fs

(* Useful function to convert unknown bitstring fragments into
 * printable strings.
 *)
let rec print_bitstring bits =
  let str = Bitstring.string_of_bitstring bits in
  print_binary_string str
and print_binary_string str =
  let rec printable = function
    | '\x00' -> "\\0" | '\x01' -> "\\1" | '\x02' -> "\\2" | '\x03' -> "\\3"
    | '\x04' -> "\\4" | '\x05' -> "\\5" | '\x06' -> "\\6" | '\x07' -> "\\7"
    | ('\x08'..'\x31' as c)
    | ('\x7f'..'\xff' as c) -> sprintf "\\x%02x" (Char.code c)
    | ('\x32'..'\x7e' as c) -> String.make 1 c
  and repeat str = function
    | n when n <= 0 -> ""
    | n -> str ^ repeat str (n-1)
  in
  let chars = String.explode str in
  let rec loop acc = function
    | [] -> List.rev acc
    | x :: xs ->
        let rec loop2 i = function
          | y :: ys when x = y -> loop2 (i+1) ys
          | ys -> i, ys
        in
        let count, ys = loop2 1 xs in
        let acc = (count, x) :: acc in
        loop acc ys
  in
  let frags = loop [] chars in
  let frags =
    List.map (function
              | (nr, x) when nr <= 4 -> repeat (printable x) nr
              | (nr, x) -> sprintf "%s<%d times>" (printable x) nr
             ) frags in
  "\"" ^ String.concat "" frags ^ "\""

(* Convert an offset from the file to an offset.  The only special
 * thing is that 0xffffffff in the file is used as a kind of "NULL
 * pointer".  We map these null values to -1.
 *)
let get_offset = function
  | 0xffffffff_l -> -1
  | i -> Int32.to_int i

(* Print an offset. *)
let print_offset = function
  | -1 -> "NULL"
  | i -> sprintf "@%08x" i

(* Print time. *)
let print_time t =
  let tm = Unix.gmtime t in
  sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(* Print UTF16LE. *)
let print_utf16 str =
  let n = String.length str in
  if n land 1 <> 0 then
    print_binary_string str
  else (
    let rec loop i =
      if i < n-1 then (
        let c1 = Char.code (str.[i]) in
        let c2 = Char.code (str.[i+1]) in
        if c1 <> 0 || c2 <> 0 then (
          (* Well, this doesn't print non-7bit-ASCII ... *)
          let c =
            if c2 = 0 then String.make 1 (Char.chr c1)
            else sprintf "\\u%04d" (c2 * 256 + c1) in
          c :: loop (i+2)
        ) else []
      ) else []
    in
    let frags = loop 0 in
    "L\"" ^ String.concat "" frags ^ "\""
  )

(* A map of int -> anything. *)
module IntMap = Map.Make (struct type t = int let compare = compare end)

(* A set of ints. *)
module IntSet = Set.Make (struct type t = int let compare = compare end)

(* Print registry vk-record type field. *)
let print_vk_type = function
  | 0 -> "NONE"
  | 1 -> "SZ"
  | 2 -> "EXPAND_SZ"
  | 3 -> "BINARY"
  | 4 -> "DWORD"
  | 5 -> "DWORD_BIG_ENDIAN"
  | 6 -> "LINK"
  | 7 -> "MULTI_SZ"
  | 8 -> "RESOURCE_LiST"
  | 9 -> "FULL_RESOURCE_DESCRIPTOR"
  | 10 -> "RESOURCE_REQUIREMENTS_LIST"
  | 11 -> "QWORD"
  | i -> sprintf "UNKNOWN_VK_TYPE_%d" i

(* XXX We should write a more efficient version of this and
 * push it into the bitstring library.
 *)
let is_zero_bitstring bits =
  let len = Bitstring.bitstring_length bits in
  let zeroes = Bitstring.zeroes_bitstring len in
  0 = Bitstring.compare bits zeroes

let is_zero_guid = is_zero_bitstring

(* http://msdn.microsoft.com/en-us/library/aa373931(VS.85).aspx
 * Endianness of GUIDs is not clear from the MSDN documentation,
 * so this is just a guess.
 *)
let print_guid bits =
  bitmatch bits with
  | { data1 : 4*8 : littleendian;
      data2 : 2*8 : littleendian;
      data3 : 2*8 : littleendian;
      data4_1 : 2*8 : littleendian;
      data4_2 : 6*8 : littleendian } ->
      sprintf "%08lX-%04X-%04X-%04X-%012LX" data1 data2 data3 data4_1 data4_2
  | { _ } ->
      assert false

(* Fold over little-endian 32-bit integers in a bitstring. *)
let rec bitstring_fold_left_int32_le f a bits =
  bitmatch bits with
  | { i : 4*8 : littleendian;
      rest : -1 : bitstring } ->
      bitstring_fold_left_int32_le f (f a i) rest
  | { rest : -1 : bitstring } when Bitstring.bitstring_length rest = 0 -> a
  | { _ } ->
      invalid_arg "bitstring_fold_left_int32_le: length not a multiple of 32 bits"
