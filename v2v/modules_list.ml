(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

let input_modules = ref []
and output_modules = ref []

let register_input_module name = List.push_front name input_modules
and register_output_module name = List.push_front name output_modules

let input_modules () = List.sort compare !input_modules
and output_modules () = List.sort compare !output_modules

type inspection_fn = Types.inspect -> bool

type conversion_fn =
  Guestfs.guestfs -> Types.inspect -> Types.source -> Types.output_settings ->
  Types.requested_guestcaps -> Types.guestcaps

let convert_modules = ref []

let register_convert_module inspect_fn name conversion_fn =
  List.push_front (inspect_fn, (name, conversion_fn)) convert_modules

let find_convert_module inspect =
  let rec loop = function
    | [] -> raise Not_found
    | (inspect_fn, ret) :: _ when inspect_fn inspect -> ret
    | _ :: rest -> loop rest
  in
  loop !convert_modules

let convert_modules () =
  List.sort compare (List.map (fun (_, (name, _)) -> name) !convert_modules)
