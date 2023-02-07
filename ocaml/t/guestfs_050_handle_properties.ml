(* libguestfs OCaml tests
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

let _ =
  let g = new Guestfs.guestfs () in
  let v = g#get_verbose () in
  g#set_verbose v;
  let v = g#get_trace () in
  g#set_trace v;
  let v = g#get_memsize () in
  g#set_memsize v;
  let v = g#get_path () in
  g#set_path (Some v)

let () = Gc.compact ()
