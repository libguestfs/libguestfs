(* virt-builder
 * Copyright (C) 2015 Red Hat Inc.
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

open Std_utils
open Common_utils
open Common_gettext.Gettext

open Printf

type csum_t =
| SHA1 of string
| SHA256 of string
| SHA512 of string

exception Mismatched_checksum of (csum_t * string)

let string_of_csum_t = function
  | SHA1 _ -> "sha1"
  | SHA256 _ -> "sha256"
  | SHA512 _ -> "sha512"

let string_of_csum = function
  | SHA1 c -> c
  | SHA256 c -> c
  | SHA512 c -> c

let of_string csum_type csum_value =
  match String.lowercase_ascii csum_type with
  | "sha1" -> SHA1 csum_value
  | "sha256" -> SHA256 csum_value
  | "sha512" -> SHA512 csum_value
  | _ -> invalid_arg csum_type

let compute_checksum csum_type ?tar filename =
  let prog =
    match csum_type with
    | "sha1" -> "sha1sum"
    | "sha256" -> "sha256sum"
    | "sha512" -> "sha512sum"
    | _ -> error (f_"unhandled checksum type ‘%s’") csum_type
  in
  let cmd =
    match tar with
    | None ->
      sprintf "%s %s" prog (quote filename)
    | Some tar ->
      sprintf "tar xOf %s %s | %s"
        (quote tar) (quote filename) prog
  in
  let lines = external_command cmd in
  match lines with
  | [] ->
    error (f_"%s did not return any output") prog
  | line :: _ ->
    let csum_str = fst (String.split " " line) in
    of_string csum_type csum_str

let verify_checksum csum ?tar filename =
  let csum_type = string_of_csum_t csum in
  let csum_actual = compute_checksum csum_type ?tar filename in
  if csum <> csum_actual then
    raise (Mismatched_checksum (csum, (string_of_csum csum_actual)))

let verify_checksums checksums filename =
  List.iter (fun c -> verify_checksum c filename) checksums
