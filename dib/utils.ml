(* virt-dib
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

open Printf

let quote = Filename.quote

let unit_GB howmany =
  (Int64.of_int howmany) *^ 1024_L *^ 1024_L *^ 1024_L

let current_arch () =
  (* Turn a CPU into the dpkg architecture naming. *)
  match Guestfs_config.host_cpu with
  | "amd64" | "x86_64" -> "amd64"
  | "i386" | "i486" | "i586" | "i686" -> "i386"
  | arch when String.is_prefix arch "armv" -> "armhf"
  | arch -> arch

let output_filename image_name = function
  | fmt -> image_name ^ "." ^ fmt

let log_filename () =
  let tm = Unix.gmtime (Unix.time ()) in
  sprintf "%s-%d%02d%02d-%02d%02d%02d.log"
    prog (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let var_from_lines var lines =
  let var_with_equal = var ^ "=" in
  let var_lines = List.filter (fun x -> String.is_prefix x var_with_equal) lines in
  match var_lines with
  | [] ->
    error (f_"variable '%s' not found in lines:\n%s")
      var (String.concat "\n" lines)
  | [x] -> snd (String.split "=" x)
  | _ ->
    error (f_"variable '%s' has more than one occurrency in lines:\n%s")
      var (String.concat "\n" lines)

let string_index_fn fn str =
  let len = String.length str in
  let rec loop i =
    if i = len then raise Not_found
    else if fn str.[i] then i
    else loop (i + 1) in
  loop 0

let digit_prefix_compare a b =
  let myint str =
    try int_of_string str
    with _ -> 0 in
  let mylength str =
    match String.length str with
    | 0 -> max_int
    | x -> x in
  let split_prefix str =
    let len = String.length str in
    let digits =
      try string_index_fn (fun x -> not (isdigit x)) str
      with Not_found -> len in
    match digits with
    | 0 -> "", str
    | x when x = len -> str, ""
    | _ -> String.sub str 0 digits, String.sub str digits (len - digits) in

  let pref_a, rest_a = split_prefix a in
  let pref_b, rest_b = split_prefix b in
  match mylength pref_a, mylength pref_b, compare (myint pref_a) (myint pref_b) with
  | x, y, 0 when x = y -> compare rest_a rest_b
  | x, y, 0 -> x - y
  | _, _, x -> x

let do_mkdir dir =
  mkdir_p dir 0o755

let rec remove_dups = function
  | [] -> []
  | x :: xs -> x :: (remove_dups (List.filter ((<>) x) xs))

let require_tool tool =
  try ignore (which tool)
  with Executable_not_found tool ->
    error (f_"%s needed but not found") tool

let do_cp src destdir =
  let cmd = [ "cp"; "-t"; destdir; "-a"; src ] in
  if run_command cmd <> 0 then exit 1

let ensure_trailing_newline str =
  if String.length str > 0 && str.[String.length str - 1] <> '\n' then str ^ "\n"
  else str

let not_in_list l e =
  not (List.mem e l)
