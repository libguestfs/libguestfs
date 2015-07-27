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

open Common_gettext.Gettext
open Common_utils

open Utils

open Printf

type csum_t =
| SHA256 of string
| SHA512 of string

let string_of_csum_t = function
  | SHA256 _ -> "sha256"
  | SHA512 _ -> "sha512"

let string_of_csum = function
  | SHA256 c -> c
  | SHA512 c -> c

let verify_checksum csum filename =
  let prog, csum_ref =
    match csum with
    | SHA256 c -> "sha256sum", c
    | SHA512 c -> "sha512sum", c
  in

  let cmd = sprintf "%s %s" prog (quote filename) in
  if verbose () then printf "%s\n%!" cmd;
  let lines = external_command cmd in
  match lines with
  | [] ->
    error (f_"%s did not return any output") prog
  | line :: _ ->
    let csum_actual = fst (string_split " " line) in
    if csum_ref <> csum_actual then
      error (f_"%s checksum of template did not match the expected checksum!\n  found checksum: %s\n  expected checksum: %s\nTry:\n - Use the '-v' option and look for earlier error messages.\n - Delete the cache: virt-builder --delete-cache\n - Check no one has tampered with the website or your network!")
        (string_of_csum_t csum) csum_actual csum_ref

let verify_checksums checksums filename =
  List.iter (fun c -> verify_checksum c filename) checksums
