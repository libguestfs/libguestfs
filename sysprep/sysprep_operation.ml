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

open Printf

type flag = [ `Created_files ]

type operation = {
  name : string;
  pod_description : string;
  extra_args : ((Arg.key * Arg.spec * Arg.doc) * string) list;
  perform : Guestfs.guestfs -> string -> flag list;
}

let ops = ref []

module OperationSet = Set.Make (
  struct
    type t = operation
    let compare a b = compare a.name b.name
  end
)
type set = OperationSet.t

let empty_set = OperationSet.empty

let add_to_set name set =
  let op = List.find (fun { name = n } -> name = n) !ops in
  OperationSet.add op set

let register_operation op = ops := op :: !ops

let baked = ref false
let rec bake () =
  let ops' = List.sort (fun { name = a } { name = b } -> compare a b) !ops in
  check_no_dupes ops';
  List.iter check ops';
  ops := ops';
  baked := true
and check_no_dupes ops =
  ignore (
    List.fold_left (
      fun opset op ->
        if OperationSet.mem op opset then (
          eprintf "virt-sysprep: duplicate operation name (%s)\n" op.name;
          exit 1
        );
        add_to_set op.name opset
    ) empty_set ops
  )
and check op =
  let n = String.length op.name in
  if n = 0 then (
    eprintf "virt-sysprep: operation name is an empty string\n";
    exit 1;
  );
  for i = 0 to n-1 do
    match String.unsafe_get op.name i with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' -> ()
    | c ->
      eprintf "virt-sysprep: disallowed character (%c) in operation name\n" c;
      exit 1
  done;
  let n = String.length op.pod_description in
  if n = 0 then (
    eprintf "virt-sysprep: operation %s has no POD\n" op.name;
    exit 1
  );
  if op.pod_description.[n-1] = '\n' then (
    eprintf "virt-sysprep: POD for %s must not end with newline\n" op.name;
    exit 1
  )

let extra_args () =
  assert !baked;

  List.flatten (
    List.map (fun { extra_args = extra_args } ->
      List.map fst extra_args
    ) !ops
  )

(* These internal functions are used to generate the man page. *)
let dump_pod () =
  assert !baked;

  List.iter (
    fun op ->
      printf "=head2 B<%s>\n" op.name;
      printf "\n";
      printf "%s\n\n" op.pod_description
  ) !ops

(* Skip any leading '-' characters when comparing command line args. *)
let skip_dashes str =
  let n = String.length str in
  let rec loop i =
    if i >= n then assert false
    else if str.[i] = '-' then loop (i+1)
    else i
  in
  let i = loop 0 in
  if i = 0 then str
  else String.sub str i (n-i)

let dump_pod_options () =
  assert !baked;

  let args = List.map (
    fun { name = op_name; extra_args = extra_args } ->
      List.map (fun ea -> op_name, ea) extra_args
  ) !ops in
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

  let args = List.sort (
    fun (a, _) (b, _) ->
      compare (skip_dashes a) (skip_dashes b)
  ) args in

  List.iter (
    fun (arg_name, (op_name, heading, pod)) ->
      printf "=item %s\n" heading;
      printf "(see C<%s> below)\n" op_name;
      printf "\n";
      printf "%s\n\n" pod
  ) args

let list_operations () =
  assert !baked;

  (* For compatibility with old shell version, list just the operation
   * names, sorted.
   *)
  List.iter (fun op -> print_endline op.name ) !ops

let perform_operations ?operations g root =
  assert !baked;

  let ops =
    match operations with
    | None -> !ops (* all operations *)
    | Some opset -> (* just the operation names listed *)
      OperationSet.elements opset in

  let flags = List.map (fun op -> op.perform g root) ops in

  List.flatten flags
