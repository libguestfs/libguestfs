(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

open Common_utils

open Printf

open Common_gettext.Gettext

class filesystem_side_effects =
object
  val mutable m_created_file = false
  val mutable m_changed_file = false
  method created_file () = m_created_file <- true
  method get_created_file = m_created_file
  method changed_file () = m_changed_file <- true
  method get_changed_file = m_changed_file
end

class device_side_effects = object end

type 'a callback = Guestfs.guestfs -> string -> 'a -> unit

type operation = {
  order : int;
  name : string;
  enabled_by_default : bool;
  heading : string;
  pod_description : string option;
  pod_notes : string option;
  extra_args : extra_arg list;
  not_enabled_check_args : unit -> unit;
  perform_on_filesystems : filesystem_side_effects callback option;
  perform_on_devices : device_side_effects callback option;
}
and extra_arg = {
  extra_argspec : Arg.key * Arg.spec * Arg.doc;
  extra_pod_argval : string option;
  extra_pod_description : string;
}

let defaults = {
  order = 0;
  name = "";
  enabled_by_default = false;
  heading = "";
  pod_description = None;
  pod_notes = None;
  extra_args = [];
  not_enabled_check_args = (fun () -> ());
  perform_on_filesystems = None;
  perform_on_devices = None;
}

let all_operations = ref []
let enabled_by_default_operations = ref []

module OperationSet = Set.Make (
  struct
    type t = operation
    let compare a b = compare a.name b.name
  end
)
type set = OperationSet.t

let empty_set = OperationSet.empty

let opset_of_oplist li =
  List.fold_left (
    fun acc elem ->
      OperationSet.add elem acc
  ) empty_set li

let add_to_set name set =
  let op = List.find (fun { name = n } -> name = n) !all_operations in
  OperationSet.add op set

let add_defaults_to_set set =
  OperationSet.union set (opset_of_oplist !enabled_by_default_operations)

let add_all_to_set set =
  opset_of_oplist !all_operations

let remove_from_set name set =
  let name_filter = fun { name = n } -> name = n in
  if List.exists name_filter !all_operations <> true then
    raise Not_found;
  OperationSet.diff set (OperationSet.filter name_filter set)

let remove_defaults_from_set set =
  OperationSet.diff set (opset_of_oplist !enabled_by_default_operations)

let remove_all_from_set set =
  empty_set

let register_operation op =
  push_front op all_operations;
  if op.enabled_by_default then
    push_front op enabled_by_default_operations

let baked = ref false
let rec bake () =
  (* Note we actually want all_operations to be sorted by name,
   * ignoring the order field.
   *)
  let ops =
    List.sort (fun { name = a } { name = b } -> compare a b) !all_operations in
  check_no_dupes ops;
  List.iter check ops;
  all_operations := ops;
  baked := true
and check_no_dupes ops =
  ignore (
    List.fold_left (
      fun opset op ->
        if OperationSet.mem op opset then
          error (f_"duplicate operation name (%s)") op.name;
        add_to_set op.name opset
    ) empty_set ops
  )
and check op =
  let n = String.length op.name in
  if n = 0 then
    error (f_"operation name is an empty string");
  for i = 0 to n-1 do
    match String.unsafe_get op.name i with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' -> ()
    | c ->
      error (f_"disallowed character (%c) in operation name") c
  done;
  let n = String.length op.heading in
  if n = 0 then
    error (f_"operation %s has no heading") op.name;
  if op.heading.[n-1] = '\n' || op.heading.[n-1] = '.' then
    error (f_"heading for %s must not end with newline or period") op.name;
  (match op.pod_description with
  | None -> ()
  | Some description ->
    let n = String.length description in
    if n = 0 then
      error (f_"operation %s has no POD") op.name;
    if description.[n-1] = '\n' then
      error (f_"POD for %s must not end with newline") op.name;
  );
  (match op.pod_notes with
  | None -> ()
  | Some notes ->
    let n = String.length notes in
    if n = 0 then
      error (f_"operation %s has no POD notes") op.name;
    if notes.[n-1] = '\n' then
      error (f_"POD notes for %s must not end with newline") op.name;
  )

let extra_args () =
  assert !baked;

  List.flatten (
    List.map (fun { extra_args = extra_args } ->
      List.map (fun { extra_argspec = argspec } -> argspec) extra_args
    ) !all_operations
  )

(* These internal functions are used to generate the man page. *)
let dump_pod () =
  assert !baked;

  List.iter (
    fun op ->
      printf "=head2 B<%s>\n" op.name;
      if op.enabled_by_default then printf "*\n";
      printf "\n";
      printf "%s.\n\n" op.heading;
      may (printf "%s\n\n") op.pod_description;
      (match op.pod_notes with
      | None -> ()
      | Some notes ->
        printf "=head3 ";
        printf (f_"Notes on %s") op.name;
        printf "\n\n";
        printf "%s\n\n" notes
      )
  ) !all_operations

let dump_pod_options () =
  assert !baked;

  let args = List.map (
    fun { name = op_name; extra_args = extra_args } ->
      List.map (fun ea -> op_name, ea) extra_args
  ) !all_operations in
  let args = List.flatten args in
  let args = List.map (
    function
    | (op_name,
       { extra_argspec = (arg_name,
                          (Arg.Unit _ | Arg.Bool _ | Arg.Set _ | Arg.Clear _),
                          _);
         extra_pod_argval = None;
         extra_pod_description = pod }) ->
      let heading = sprintf "B<%s>" arg_name in
      arg_name, (op_name, heading, pod)

    | (op_name,
       { extra_argspec = (arg_name,
                          (Arg.String _ | Arg.Set_string _ | Arg.Int _ |
                           Arg.Set_int _ | Arg.Float _ | Arg.Set_float _),
                          _);
         extra_pod_argval = Some arg_val;
         extra_pod_description = pod }) ->
      let heading = sprintf "B<%s> %s" arg_name arg_val in
      arg_name, (op_name, heading, pod)

    | _ ->
      failwith "sysprep_operation.ml: argument type not implemented"
  ) args in

  let args =
    List.sort (fun (a, _) (b, _) -> compare_command_line_args a b) args in

  List.iter (
    fun (arg_name, (op_name, heading, pod)) ->
      printf "=item %s\n" heading;
      printf "(see C<%s> below)\n" op_name;
      printf "\n";
      printf "%s\n\n" pod
  ) args

let list_operations () =
  assert !baked;

  List.iter (
    fun op ->
      printf "%s %s %s\n" op.name
        (if op.enabled_by_default then "*" else " ")
        op.heading
  ) !all_operations

let not_enabled_check_args ?operations () =
  let enabled_ops =
    match operations with
    | None -> !enabled_by_default_operations
    | Some opset -> (* just the operation names listed *)
      OperationSet.elements opset in
  let all_ops = opset_of_oplist !all_operations in
  let enabled_ops = opset_of_oplist enabled_ops in
  let disabled_ops = OperationSet.diff all_ops enabled_ops in
  OperationSet.iter (fun op -> op.not_enabled_check_args ()) disabled_ops

let compare_operations { order = o1; name = n1 } { order = o2; name = n2 } =
  let i = compare o1 o2 in
  if i <> 0 then i else compare n1 n2

let perform_operations_on_filesystems ?operations g root
    side_effects =
  assert !baked;

  let ops =
    match operations with
    | None -> !enabled_by_default_operations
    | Some opset -> (* just the operation names listed *)
      OperationSet.elements opset in

  (* Perform the operations in alphabetical, rather than random order. *)
  let ops = List.sort compare_operations ops in

  List.iter (
    function
    | { name = name; perform_on_filesystems = Some fn } ->
      message (f_"Performing %S ...") name;
      fn g root side_effects
    | { perform_on_filesystems = None } -> ()
  ) ops

let perform_operations_on_devices ?operations g root
    side_effects =
  assert !baked;

  let ops =
    match operations with
    | None -> !enabled_by_default_operations
    | Some opset -> (* just the operation names listed *)
      OperationSet.elements opset in

  (* Perform the operations in alphabetical, rather than random order. *)
  let ops = List.sort compare_operations ops in

  List.iter (
    function
    | { name = name; perform_on_devices = Some fn } ->
      message (f_"Performing %S ...") name;
      fn g root side_effects
    | { perform_on_devices = None } -> ()
  ) ops
