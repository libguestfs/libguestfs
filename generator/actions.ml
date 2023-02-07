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
open Types
open Utils

(* non_daemon_functions are any functions which don't get processed
 * in the daemon, eg. functions for setting and getting local
 * configuration values.
 *)

let non_daemon_functions =
  Actions_internal_tests.test_functions @
  Actions_internal_tests.test_support_functions @
  Actions_core.non_daemon_functions @
  Actions_core_deprecated.non_daemon_functions @
  Actions_debug.non_daemon_functions @
  Actions_inspection.non_daemon_functions @
  Actions_inspection_deprecated.non_daemon_functions @
  Actions_properties.non_daemon_functions @
  Actions_properties_deprecated.non_daemon_functions @
  Actions_tsk.non_daemon_functions @
  Actions_yara.non_daemon_functions

(* daemon_functions are any functions which cause some action
 * to take place in the daemon.
 *)

let daemon_functions =
  Actions_augeas.daemon_functions @
  Actions_core.daemon_functions @
  Actions_core_deprecated.daemon_functions @
  Actions_debug.daemon_functions @
  Actions_hivex.daemon_functions @
  Actions_hivex_deprecated.daemon_functions @
  Actions_inspection.daemon_functions @
  Actions_inspection_deprecated.daemon_functions @
  Actions_tsk.daemon_functions @
  Actions_yara.daemon_functions

(* Some post-processing of the basic lists of actions. *)

(* Add the name of the C function:
 * c_name = short name, used by C bindings so we know what to export
 * c_function = full name that non-C bindings should call
 * c_optarg_prefix = prefix for optarg / bitmask names
 *)
let test_functions, non_daemon_functions, daemon_functions =
  let make_c_function f =
    match f with
    | { style = _, _, [] } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name;
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name }
    | { style = _, _, (_::_); once_had_no_optargs = false } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name ^ "_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name }
    | { style = _, _, (_::_); once_had_no_optargs = true } ->
      { f with
          c_name = f.name ^ "_opts";
          c_function = "guestfs_" ^ f.name ^ "_opts_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name
                            ^ "_OPTS";
          non_c_aliases = [ f.name ^ "_opts" ] }
  in
  let test_functions =
    List.map make_c_function Actions_internal_tests.test_functions in
  let non_daemon_functions = List.map make_c_function non_daemon_functions in
  let daemon_functions = List.map make_c_function daemon_functions in
  test_functions, non_daemon_functions, daemon_functions

(* Create a camel-case version of each name, unless the camel_name
 * field was set above.
 *)
let non_daemon_functions, daemon_functions =
  let make_camel_case name =
    List.fold_left (
      fun a b ->
        a ^ String.uppercase_ascii (Str.first_chars b 1) ^ Str.string_after b 1
    ) "" (String.nsplit "_" name)
  in
  let make_camel_case_if_not_set f =
    if f.camel_name = "" then
      { f with camel_name = make_camel_case f.name }
    else
      f
  in
  let non_daemon_functions =
    List.map make_camel_case_if_not_set non_daemon_functions in
  let daemon_functions =
    List.map make_camel_case_if_not_set daemon_functions in
  non_daemon_functions, daemon_functions

(* Verify that no proc_nr field is set.  These are added from
 * [proc_nr.ml] and must not be present in the [actions_*.ml] files.
 *)
let () =
  let check_no_proc_nr = function
    | { proc_nr = None } -> ()
    | { name = name; proc_nr = Some _ } ->
       failwithf "definition of %s must not include proc_nr, use proc_nr.ml to define procedure numbers" name
  in
  List.iter check_no_proc_nr non_daemon_functions;
  List.iter check_no_proc_nr daemon_functions

(* Now add proc_nr to all daemon functions using the mapping table
 * from [proc_nr.ml].
 *)
let daemon_functions =
  let assoc =
    let map = List.map (fun (nr, name) -> (name, nr)) Proc_nr.proc_nr in
    fun name ->
      try List.assoc name map
      with Not_found ->
        failwithf "no proc_nr listed for %s" name
  in
  List.map (
    fun f -> { f with proc_nr = Some (assoc f.name) }
  ) daemon_functions

(* Check there are no entries in the proc_nr table which aren't
 * associated with a daemon function.
 *)
let () =
  List.iter (
    fun (_, name) ->
      if not (List.exists (fun { name = n } -> name = n) daemon_functions) then
        failwithf "proc_nr entry for %s does not correspond to a daemon function"
                  name
  ) Proc_nr.proc_nr

(* All functions. *)
let actions = non_daemon_functions @ daemon_functions

(* Filters which can be applied. *)
let is_non_daemon_function = function
  | { proc_nr = None } -> true
  | { proc_nr = Some _ } -> false
let non_daemon_functions = List.filter is_non_daemon_function

let is_daemon_function f = not (is_non_daemon_function f)
let daemon_functions = List.filter is_daemon_function

let is_external { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest | VBindTest | VDebug -> true
  | VInternal -> false
let external_functions = List.filter is_external

let is_internal f = not (is_external f)
let internal_functions = List.filter is_internal

let is_documented { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest -> true
  | VBindTest | VDebug | VInternal -> false
let documented_functions = List.filter is_documented

let is_fish { visibility = v; style = (_, args, _) } =
  (* Internal functions are not exported to guestfish. *)
  match v with
  | VPublicNoFish | VStateTest | VBindTest | VInternal -> false
  | VPublic | VDebug ->
    (* Functions that take Pointer parameters cannot be used in
     * guestfish, since there is no way the user could safely
     * generate a pointer.
     *)
    not (List.exists (function Pointer _ -> true | _ -> false) args)
let fish_functions = List.filter is_fish

let is_ocaml_function = function
  | { impl = OCaml _ } -> true
  | { impl = C } -> false
let impl_ocaml_functions = List.filter is_ocaml_function

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let sort = List.sort action_compare

(* Find a single action by name, or give an error. *)
let find name =
  try List.find (fun { name = n } -> n = name) actions
  with Not_found -> failwithf "could not find action named ‘%s’" name
