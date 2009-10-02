(* libguestfs OCaml bindings
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *)

open Unix

let (//) = Filename.concat
let dotdot = Filename.parent_dir_name

let read_file name =
  let chan = open_in name in
  let lines = ref [] in
  let lines =
    try while true do lines := input_line chan :: !lines done; []
    with End_of_file -> List.rev !lines in
  close_in chan;
  String.concat "" lines

let parse name =
  let xml = read_file name in
  let os = Guestfs_inspector.inspect ~xml [] in
  os

let () =
  ignore (parse (dotdot // "inspector" // "example1.xml"));
  ignore (parse (dotdot // "inspector" // "example2.xml"));
  ignore (parse (dotdot // "inspector" // "example3.xml"));
  ignore (parse (dotdot // "inspector" // "example4.xml"))
