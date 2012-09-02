(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Utils

let hash = Hashtbl.create 13

let load_api_versions filename =
  let chan = open_in filename in
  let rec loop lineno =
    let line = input_line chan in
    let sym, ver =
      match string_split " " line with
      | [ sym; ver ] -> sym, ver
      | _ ->
          failwithf "%s: %d: invalid input in API versions file"
            filename lineno in
    Hashtbl.replace hash sym ver;
    loop (lineno+1)
  in
  (try loop 1 with End_of_file -> ());
  close_in chan

let lookup_api_version sym =
  try Some (Hashtbl.find hash sym)
  with Not_found -> None
