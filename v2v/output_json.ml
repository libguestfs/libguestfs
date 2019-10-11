(* virt-v2v
 * Copyright (C) 2019 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Types
open Utils

type json_options = {
  json_disks_pattern : string;
}

let print_output_options () =
  printf (f_"Output options (-oo) which can be used with -o json:

  -oo json-disks-pattern=PATTERN   Pattern for the disks.
")

let known_pattern_variables = ["DiskNo"; "DiskDeviceName"; "GuestName"]

let parse_output_options options =
  let json_disks_pattern = ref None in

  List.iter (
    function
    | "json-disks-pattern", v ->
       if !json_disks_pattern <> None then
         error (f_"-o json: -oo json-disks-pattern set more than once");
       let vars =
         try Var_expander.scan_variables v
         with Var_expander.Invalid_variable var ->
           error (f_"-o json: -oo json-disks-pattern: invalid variable %%{%s}")
             var in
       List.iter (
         fun var ->
           if not (List.mem var known_pattern_variables) then
             error (f_"-o json: -oo json-disks-pattern: unhandled variable %%{%s}")
               var
       ) vars;
       json_disks_pattern := Some v
    | k, _ ->
       error (f_"-o json: unknown output option ‘-oo %s’") k
  ) options;

  let json_disks_pattern =
    Option.default "%{GuestName}-%{DiskDeviceName}" !json_disks_pattern in

  { json_disks_pattern }

class output_json dir json_options = object
  inherit output

  method as_options = sprintf "-o json -os %s" dir

  method prepare_targets source_name overlays _ _ _ _ =
    List.mapi (
      fun i (_, ov) ->
        let outname =
          let vars_fn = function
            | "DiskNo" -> Some (string_of_int (i+1))
            | "DiskDeviceName" -> Some ov.ov_sd
            | "GuestName" -> Some source_name
            | _ -> assert false
          in
          Var_expander.replace_fn json_options.json_disks_pattern vars_fn in
        let destname = dir // outname in
        mkdir_p (Filename.dirname destname) 0o755;
        TargetFile destname
    ) overlays

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method create_metadata source targets
                         target_buses guestcaps inspect target_firmware =
    let doc =
      Create_json.create_json_metadata source targets target_buses
                                       guestcaps inspect target_firmware in
    let doc_string = JSON.string_of_doc ~fmt:JSON.Indented doc in

    if verbose () then (
      eprintf "resulting JSON:\n";
      output_string stderr doc_string;
      eprintf "\n\n%!";
    );

    let name = source.s_name in
    let file = dir // name ^ ".json" in

    with_open_out file (
      fun chan ->
        output_string chan doc_string;
        output_char chan '\n'
    )
end

let output_json = new output_json
let () = Modules_list.register_output_module "json"
