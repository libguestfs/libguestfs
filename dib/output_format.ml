(* virt-dib
 * Copyright (C) 2012-2019 Red Hat Inc.
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
open Getopt.OptionName

open Utils

type format = {
  name : string;
  extra_args : extra_arg list;
  output_to_file : bool;
  check_prerequisites : (unit -> unit) option;
  check_appliance_prerequisites : (Guestfs.guestfs -> unit) option;
  run_on_filesystem : (Guestfs.guestfs -> string -> string -> unit) option;
  run_on_file : (string -> (string * string) -> string -> unit) option;
}
and extra_arg = {
  extra_argspec : Getopt.keys * Getopt.spec * Getopt.doc;
}

let defaults = {
  name = "";
  extra_args = [];
  output_to_file = true;
  check_prerequisites = None;
  check_appliance_prerequisites = None;
  run_on_filesystem = None;
  run_on_file = None;
}

let all_formats = ref []

module FormatSet = Set.Make (
  struct
    type t = format
    let compare a b = compare a.name b.name
  end
)
type set = FormatSet.t

let empty_set = FormatSet.empty

let add_to_set name set =
  let op = List.find (fun { name = n } -> name = n) !all_formats in
  FormatSet.add op set

let set_mem x set =
  FormatSet.exists (fun { name = n } -> n = x) set

let set_cardinal set =
  FormatSet.cardinal set

let register_format op =
  List.push_front op all_formats

let baked = ref false
let rec bake () =
  (* Note we actually want all_formats to be sorted by name,
   * ignoring the order field.
   *)
  let ops =
    List.sort (fun { name = a } { name = b } -> compare a b) !all_formats in
  check_no_dupes ops;
  List.iter check ops;
  all_formats := ops;
  baked := true
and check_no_dupes ops =
  ignore (
    List.fold_left (
      fun opset op ->
        if FormatSet.mem op opset then
          error (f_"duplicate format name (%s)") op.name;
        add_to_set op.name opset
    ) empty_set ops
  )
and check op =
  let n = String.length op.name in
  if n = 0 then
    error (f_"format name is an empty string");
  for i = 0 to n-1 do
    match String.unsafe_get op.name i with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' -> ()
    | c ->
      error (f_"disallowed character (%c) in format name") c
  done

let extra_args () =
  assert !baked;

  List.flatten (
    List.map (fun { extra_args } ->
      List.map (fun { extra_argspec = argspec } -> argspec) extra_args
    ) !all_formats
  )

let list_formats () =
  assert !baked;

  List.map (fun { name = n } -> n) !all_formats

let compare_formats { name = n1 } { name = n2 } =
  compare n1 n2

let check_formats_prerequisites ~formats =
  assert !baked;

  (* Run the formats in alphabetical, rather than random order. *)
  let formats = List.sort compare_formats (FormatSet.elements formats) in

  List.iter (
    function
    | { check_prerequisites = Some fn } ->
      fn ()
    | { check_prerequisites = None } -> ()
  ) formats

let check_formats_appliance_prerequisites ~formats g =
  assert !baked;

  (* Run the formats in alphabetical, rather than random order. *)
  let formats = List.sort compare_formats (FormatSet.elements formats) in

  List.iter (
    function
    | { check_appliance_prerequisites = Some fn } ->
      fn g
    | { check_appliance_prerequisites = None } -> ()
  ) formats

let run_formats_on_filesystem ~formats g image_name tmpdir =
  assert !baked;

  (* Run the formats in alphabetical, rather than random order. *)
  let formats = List.sort compare_formats (FormatSet.elements formats) in

  List.iter (
    function
    | { run_on_filesystem = Some fn; name; output_to_file } ->
      let filename =
        if output_to_file then output_filename image_name name
        else "" in
      fn g filename tmpdir
    | { run_on_filesystem = None } -> ()
  ) formats

let run_formats_on_file ~formats image_name tmpdisk tmpdir  =
  assert !baked;

  (* Run the formats in alphabetical, rather than random order. *)
  let formats = List.sort compare_formats (FormatSet.elements formats) in

  List.iter (
    function
    | { run_on_file = Some fn; name; output_to_file } ->
      let filename =
        if output_to_file then output_filename image_name name
        else "" in
      fn filename tmpdisk tmpdir
    | { run_on_file = None } -> ()
  ) formats

let get_filenames ~formats image_name =
  assert !baked;

  (* Run the formats in alphabetical, rather than random order. *)
  let formats = List.sort compare_formats (FormatSet.elements formats) in

  List.filter_map (
    function
    | { output_to_file = true; name } ->
      Some (output_filename image_name name)
    | { output_to_file = false } ->
      None
  ) formats
