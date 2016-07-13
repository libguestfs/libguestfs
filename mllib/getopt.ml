(* Command line handling for OCaml tools in libguestfs.
 * Copyright (C) 2016 Red Hat Inc.
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

open Common_gettext.Gettext

open Printf

type spec =
  | Unit of (unit -> unit)
  | Set of bool ref
  | Clear of bool ref
  | String of string * (string -> unit)
  | Set_string of string * string ref
  | Int of string * (int -> unit)
  | Set_int of string * int ref

type keys = string list
type doc = string
type usage_msg = string
type anon_fun = (string -> unit)
type c_keys = string array

type speclist = (keys * spec * doc) list

type t = {
  mutable specs : speclist;
  anon_fun : anon_fun option;
  usage_msg : usage_msg;
}

external getopt_parse : string array -> (c_keys * spec * doc) array -> ?anon_fun:anon_fun -> usage_msg -> unit = "guestfs_int_mllib_getopt_parse"

let column_wrap = 38

let show_help h () =
  let b = Buffer.create 1024 in

  let spaces n =
    String.make n ' ' in

  let prologue = sprintf (f_"%s\nOptions:\n") h.usage_msg in
  Buffer.add_string b prologue;

  List.iter (
    fun (keys, spec, doc) ->
      let columns = ref 0 in
      let add s =
        Buffer.add_string b s;
        columns := !columns + (String.length s)
      in

      add "  ";
      add (String.concat ", " keys);
      let arg =
        match spec with
        | Unit _
        | Set _
        | Clear _ -> None
        | String (arg, _)
        | Set_string (arg, _)
        | Int (arg, _)
        | Set_int (arg, _) -> Some arg in
      (match arg with
      | None -> ()
      | Some arg ->
        add (sprintf " <%s>" arg)
      );
      if !columns >= column_wrap then (
        Buffer.add_char b '\n';
        Buffer.add_string b (spaces column_wrap);
      ) else (
        Buffer.add_string b (spaces (column_wrap - !columns));
      );
      Buffer.add_string b doc;
      Buffer.add_char b '\n';
  ) h.specs;

  Buffer.output_buffer stdout b;
  exit 0

let is_prefix str prefix =
  let n = String.length prefix in
  String.length str >= n && String.sub str 0 n = prefix

(* Implement `--short-options' and `--long-options'. *)
let display_short_options h () =
  List.iter (
    fun (args, _, _) ->
      List.iter (
        fun arg ->
          if is_prefix arg "-" && not (is_prefix arg "--") then
            printf "%s\n" arg
      ) args
  ) h.specs;
  exit 0
let display_long_options h () =
  List.iter (
    fun (args, _, _) ->
      List.iter (
        fun arg ->
          if is_prefix arg "--" && arg <> "--long-options" &&
               arg <> "--short-options" then
            printf "%s\n" arg
      ) args
  ) h.specs;
  exit 0

(* Skip any leading '-' characters when comparing command line args. *)
let skip_dashes str =
  let n = String.length str in
  let rec loop i =
    if i >= n then invalid_arg "skip_dashes"
    else if String.unsafe_get str i = '-' then loop (i+1)
    else i
  in
  let i = loop 0 in
  if i = 0 then str
  else String.sub str i (n-i)

let compare_command_line_args a b =
  compare (String.lowercase (skip_dashes a)) (String.lowercase (skip_dashes b))

let create specs ?anon_fun usage_msg =
  (* Sanity check the input *)
  let validate_key key =
    if String.length key == 0 || key == "-" || key == "--"
       || key.[0] != '-' then
      invalid_arg (sprintf "invalid option key: '%s'" key)
  in

  List.iter (
    fun (keys, spec, doc) ->
      if keys == [] then
        invalid_arg "empty keys for Getopt spec";
      List.iter validate_key keys;
  ) specs;

  let t =
    {
      specs = [];  (* Set it later, with own options, and sorted.  *)
      anon_fun = anon_fun;
      usage_msg = usage_msg;
    } in

  let specs = specs @ [
    [ "--short-options" ], Unit (display_short_options t), s_"List short options (internal)";
    [ "--long-options" ], Unit (display_long_options t), s_"List long options (internal)";
  ] in

  (* Decide whether the help option can be added, and which switches use.  *)
  let has_dash_help = ref false in
  let has_dash_dash_help = ref false in
  List.iter (
    fun (keys, _, _) ->
      if not (!has_dash_help) then
        has_dash_help := List.mem "-help" keys;
      if not (!has_dash_dash_help) then
        has_dash_dash_help := List.mem "--help" keys;
  ) specs;
  let help_keys = [] @
    (if !has_dash_help then [] else [ "-help" ]) @
    (if !has_dash_dash_help then [] else [ "--help" ]) in
  let specs = specs @
    (if help_keys <> [] then [ help_keys, Unit (show_help t), s_"Display brief help"; ] else []) in

  (* Sort the specs, and set them in the handle.  *)
  let specs = List.map (
    fun (keys, action, doc) ->
      List.hd (List.sort compare_command_line_args keys), (keys, action, doc)
  ) specs in
  let specs =
    let cmp (arg1, _) (arg2, _) = compare_command_line_args arg1 arg2 in
    List.sort cmp specs in
  let specs = List.map snd specs in
  t.specs <- specs;

  t

let parse_argv t argv =
  let specs = List.map (
    fun (keys, spec, doc) ->
      Array.of_list keys, spec, doc
  ) t.specs in
  let specs = Array.of_list specs in
  getopt_parse argv specs ?anon_fun:t.anon_fun t.usage_msg

let parse t =
  parse_argv t Sys.argv
