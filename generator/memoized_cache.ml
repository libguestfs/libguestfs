(* libguestfs
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Std_utils

open Printf

type ('a, 'b) t = {
  memo : ('a, 'b) Hashtbl.t;
  filename : string;
  lookup_fn : 'a -> 'b;
  batch_size : int;
  mutable unsaved_count : int;
}

let memo_save t =
  with_open_out t.filename
                (fun chan -> output_value chan t.memo);
  t.unsaved_count <- 0

let memo_updated t =
  t.unsaved_count <- t.unsaved_count + 1;
  if t.unsaved_count >= t.batch_size then
    memo_save t

let create ?(version = 1) ?(batch_size = 100) name lookup_fn =
  let filename = sprintf "generator/.%s.data.version.%d" name version in
  let memo =
    try with_open_in filename input_value
    with _ -> Hashtbl.create 13 in
  {
    memo; filename; lookup_fn; batch_size; unsaved_count = 0;
  }

let save t =
  if t.unsaved_count > 0 then
    memo_save t

let find t key =
  try Hashtbl.find t.memo key
  with Not_found ->
    let res = t.lookup_fn key in
    Hashtbl.add t.memo key res;
    memo_updated t;
    res
