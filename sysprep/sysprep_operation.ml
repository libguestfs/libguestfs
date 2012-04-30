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

open Utils

open Printf

open Sysprep_gettext.Gettext

type flag = [ `Created_files ]

type operation = {
  name : string;
  enabled_by_default : bool;
  heading : string;
  pod_description : string option;
  extra_args : ((Arg.key * Arg.spec * Arg.doc) * string) list;
  perform : Guestfs.guestfs -> string -> flag list;
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

let add_to_set name set =
  let op = List.find (fun { name = n } -> name = n) !all_operations in
  OperationSet.add op set

let register_operation op =
  all_operations := op :: !all_operations;
  if op.enabled_by_default then
    enabled_by_default_operations := op :: !enabled_by_default_operations

let baked = ref false
let rec bake () =
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
        if OperationSet.mem op opset then (
          eprintf (f_"virt-sysprep: duplicate operation name (%s)\n") op.name;
          exit 1
        );
        add_to_set op.name opset
    ) empty_set ops
  )
and check op =
  let n = String.length op.name in
  if n = 0 then (
    eprintf (f_"virt-sysprep: operation name is an empty string\n");
    exit 1;
  );
  for i = 0 to n-1 do
    match String.unsafe_get op.name i with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' -> ()
    | c ->
      eprintf (f_"virt-sysprep: disallowed character (%c) in operation name\n")
        c;
      exit 1
  done;
  let n = String.length op.heading in
  if n = 0 then (
    eprintf (f_"virt-sysprep: operation %s has no heading\n") op.name;
    exit 1
  );
  if op.heading.[n-1] = '\n' || op.heading.[n-1] = '.' then (
    eprintf (f_"virt-sysprep: heading for %s must not end with newline or period\n")
      op.name;
    exit 1
  );
  (match op.pod_description with
  | None -> ()
  | Some description ->
    let n = String.length description in
    if n = 0 then (
      eprintf (f_"virt-sysprep: operation %s has no POD\n") op.name;
      exit 1
    );
    if description.[n-1] = '\n' then (
      eprintf (f_"virt-sysprep: POD for %s must not end with newline\n")
        op.name;
      exit 1
    )
  )

let extra_args () =
  assert !baked;

  List.flatten (
    List.map (fun { extra_args = extra_args } ->
      List.map fst extra_args
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
      (match op.pod_description with
      | None -> ()
      | Some description -> printf "%s\n\n" description
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
    fun (op_name, ((arg_name, spec, _), pod)) ->
      match spec with
      | Arg.Unit _
      | Arg.Bool _
      | Arg.Set _
      | Arg.Clear _ ->
        let heading = sprintf "B<%s>" arg_name in
        arg_name, (op_name, heading, pod)
      | Arg.String _
      | Arg.Set_string _
      | Arg.Int _
      | Arg.Set_int _
      | Arg.Float _
      | Arg.Set_float _ ->
        let heading = sprintf "B<%s> %s" arg_name (skip_dashes arg_name) in
        arg_name, (op_name, heading, pod)
      | Arg.Tuple _
      | Arg.Symbol _
      | Arg.Rest _ -> assert false (* XXX not implemented *)
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

let perform_operations ?operations ?(quiet = false) g root =
  assert !baked;

  let ops =
    match operations with
    | None -> !enabled_by_default_operations
    | Some opset -> (* just the operation names listed *)
      OperationSet.elements opset in

  let flags =
    List.map (
      fun op ->
        if not quiet then
          printf "Performing %S ...\n%!" op.name;
        op.perform g root
    ) ops in

  List.flatten flags
