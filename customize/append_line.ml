(* virt-customize
 * Copyright (C) 2016 Red Hat Inc.
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
open Tools_utils
open Common_gettext.Gettext

module G = Guestfs

let append_line (g : G.guestfs) root path line =
  (* The default line ending for this guest type.  This is only
   * used when we don't know anything more about the file.
   *)
  let default_newline () =
    match g#inspect_get_type root with
    | "windows" -> "\r\n"
    | _ -> "\n"
  in

  if not (g#exists path) then (
    g#write path (line ^ default_newline ())
  )
  else (
    (* Stat the file.  We want to know it's a regular file, and
     * also its size.
     *)
    let { G.st_mode = mode; st_size = size } = g#statns path in
    if Int64.logand mode 0o170000_L <> 0o100000_L then
      error (f_"append_line: %s is not a file") path;

    (* Guess the line ending from the first part of the file, else
     * use the default for this guest type.
     *)
    let newline =
      let content = g#pread path 8192 0L in
      if String.find content "\r\n" >= 0 then "\r\n"
      else if String.find content "\n" >= 0 then "\n"
      else if String.find content "\r" >= 0 then "\r"
      else default_newline () in

    let line = line ^ newline in

    (* Do we need to append a newline to the existing file? *)
    let last_chars =
      let len = String.length newline in
      if size <= 0L then newline (* empty file ends in virtual newline *)
      else if size >= Int64.of_int len then
        g#pread path len (size -^ Int64.of_int len)
      else
        g#pread path len 0L in
    let line =
      if last_chars = newline then line
      else newline ^ line in

    (* Finally, append. *)
    g#write_append path line
  )
