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

open Std_utils

open Printf

type spec =
  | Unit of (unit -> unit)
  | Set of bool ref
  | Clear of bool ref
  | String of string * (string -> unit)
  | Set_string of string * string ref
  | Int of string * (int -> unit)
  | Set_int of string * int ref
  | Symbol of string * string list * (string -> unit)
  | OptString of string * (string option -> unit)

module OptionName = struct
  type option_name = S of char | L of string | M of string
end
open OptionName

type keys = option_name list
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

let hidden_option_description = ""

external getopt_parse : string array -> (c_keys * spec * doc) array -> ?anon_fun:anon_fun -> usage_msg -> unit = "guestfs_int_mllib_getopt_parse"

let column_wrap = 38

(* This should only be used for --help and man pages. *)
let string_of_option_name = function
  | S c -> sprintf "-%c" c
  | L s -> "--" ^ s
  | M s -> "-" ^ s

let show_help h () =
  let b = Buffer.create 1024 in

  let spaces n =
    String.make n ' ' in

  let prologue = sprintf (f_"%s\nOptions:\n") h.usage_msg in
  Buffer.add_string b prologue;

  let specs =
    List.filter (
      fun (_, _, doc) ->
      doc <> hidden_option_description
    ) h.specs in

  List.iter (
    fun (keys, spec, doc) ->
      let columns = ref 0 in
      let add s =
        Buffer.add_string b s;
        columns := !columns + (String.length s)
      in

      add "  ";
      add (String.concat ", " (List.map string_of_option_name keys));
      let arg =
        match spec with
        | Unit _
        | Set _
        | Clear _
        | OptString _ -> None
        | String (arg, _)
        | Set_string (arg, _)
        | Int (arg, _)
        | Set_int (arg, _)
        | Symbol (arg, _, _) -> Some arg in
      let optarg =
        match spec with
        | Unit _
        | Set _
        | Clear _
        | String _
        | Set_string _
        | Int _
        | Set_int _
        | Symbol _ -> None
        | OptString (arg, _) -> Some arg in
      (match arg, optarg with
      | None, None -> ()    (* --foo *)
      | Some arg, None ->   (* --foo=val *)
        add (sprintf " <%s>" arg)
      | None, Some arg ->   (* --foo[=val] *)
        add (sprintf "[=%s]" arg)
      | Some _, Some _ ->   (* should not happen *)
        failwith "internal error: getopt: option marked both with arg and optarg"
      );
      if !columns >= column_wrap then (
        Buffer.add_char b '\n';
        Buffer.add_string b (spaces column_wrap);
      ) else (
        Buffer.add_string b (spaces (column_wrap - !columns));
      );
      Buffer.add_string b doc;
      Buffer.add_char b '\n';
  ) specs;

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
        function
        | S c -> printf "-%c\n" c
        | M s -> printf "-%s\n" s
        | L _ -> ()
      ) args
  ) h.specs;
  exit 0
let display_long_options h () =
  List.iter (
    fun (args, _, _) ->
      List.iter (
        function
        | L "short-options" | L "long-options"
        | S _ -> ()
        | L s | M s -> printf "--%s\n" s
      ) args
  ) h.specs;
  exit 0

let compare_command_line_args a b =
  let string_of_option_name_no_dashes = function
    | S c -> String.make 1 c
    | L s | M s -> s
  in
  let a = String.lowercase_ascii (string_of_option_name_no_dashes a) in
  let b = String.lowercase_ascii (string_of_option_name_no_dashes b) in
  compare a b

let create specs ?anon_fun usage_msg =
  (* Sanity check the input *)
  let validate_key = function
    | M s when String.length s <> 2 || (s.[0] <> 'i' && s.[0] <> 'o') ->
       invalid_arg "Getopt spec: invalid use of M\"...\" option - only use this for virt-v2v -iX and -oX options"
    | L"" -> invalid_arg "Getopt spec: invalid empty long option"
    | L"help" -> invalid_arg "Getopt spec: should not have L\"help\""
    | L"short-options" ->
       invalid_arg "Getopt spec: should not have L\"short-options\""
    | L"long-options" ->
       invalid_arg "Getopt spec: should not have L\"long-options\""
    | L s when s.[0] = '-' ->
       invalid_arg (sprintf "Getopt spec: L%S should not begin with a dash"
                            s)
    | L s when String.contains s '_' ->
       invalid_arg (sprintf "Getopt spec: L%S should not contain '_'"
                            s)
    | _ -> ()
  in

  let validate_spec = function
    | Unit _ -> ()
    | Set _ -> ()
    | Clear _ -> ()
    | String _ -> ()
    | Set_string _ -> ()
    | Int _ -> ()
    | Set_int _ -> ()
    | OptString _ -> ()
    | Symbol (_, elements, _) ->
      List.iter (
        fun e ->
          if String.length e == 0 || is_prefix e "-" then
            invalid_arg (sprintf "invalid element in Symbol: '%s'" e);
      ) elements;
  in

  List.iter (
    fun (keys, spec, doc) ->
      if keys == [] then
        invalid_arg "empty keys for Getopt spec";
      List.iter validate_key keys;
      validate_spec spec;
  ) specs;

  let t = {
    specs = [];      (* Set it later, with own options, and sorted. *)
    anon_fun = anon_fun;
    usage_msg = usage_msg;
  } in

  let added_options = [
    [ L"short-options" ], Unit (display_short_options t),
                                         hidden_option_description;
    [ L"long-options" ], Unit (display_long_options t),
                                         hidden_option_description;
    [ L"help" ], Unit (show_help t),     s_"Display brief help";
  ] in
  let specs = added_options @ specs in

  (* Sort the specs.  *)
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
      let keys = List.map (
        function
        | S c -> sprintf "-%c" c
        | L s | M s -> sprintf "--%s" s
      ) keys in
      let keys = Array.of_list keys in
      keys, spec, doc
  ) t.specs in
  let specs = Array.of_list specs in
  getopt_parse argv specs ?anon_fun:t.anon_fun t.usage_msg

let parse t =
  parse_argv t Sys.argv
