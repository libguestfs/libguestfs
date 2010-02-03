(* Basic counting module.

   Copyright (C) 2006 Merjis Ltd.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
*)

type 'a t = ('a, int ref) Hashtbl.t

let create () =
  Hashtbl.create 13

let get_ref counter thing =
  try
    Hashtbl.find counter thing
  with
    Not_found ->
      let r = ref 0 in
      Hashtbl.add counter thing r;
      r

let incr counter thing =
  let r = get_ref counter thing in
  incr r

let decr counter thing =
  let r = get_ref counter thing in
  decr r

let add counter thing n =
  let r = get_ref counter thing in
  r := !r + n

let sub counter thing n =
  let r = get_ref counter thing in
  r := !r - n

let set counter thing n =
  let r = get_ref counter thing in
  r := n

(* Don't use get_ref, to avoid unnecessarily creating 'ref 0's. *)
let get counter thing =
  try
    !(Hashtbl.find counter thing)
  with
    Not_found -> 0

(* This is a common pair of operations, worth optimising. *)
let incr_get counter thing =
  let r = get_ref counter thing in
  Pervasives.incr r;
  !r

let zero = Hashtbl.remove

let read counter =
  let counts =
    Hashtbl.fold (
      fun thing r xs ->
	let r = !r in
	if r <> 0 then (r, thing) :: xs
	else xs
    ) counter [] in
  List.sort (fun (a, _) (b, _) -> compare (b : int) (a : int)) counts

let length = Hashtbl.length

let total counter =
  let total = ref 0 in
  Hashtbl.iter (fun _ r -> total := !total + !r) counter;
  !total

let clear = Hashtbl.clear
