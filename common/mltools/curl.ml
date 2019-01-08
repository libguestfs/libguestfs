(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

type t = {
  curl : string;
  args : args;
  tmpdir : string option;
}
and args = (string * string option) list

let safe_args = [
  "max-redirs", Some "5";
  "globoff", None;         (* Don't glob URLs. *)
]

type proxy = UnsetProxy | SystemProxy | ForcedProxy of string

let args_of_proxy = function
  | UnsetProxy ->      [ "proxy", Some "" ; "noproxy", Some "*" ]
  | SystemProxy ->     []
  | ForcedProxy url -> [ "proxy", Some url; "noproxy", Some "" ]

let create ?(curl = "curl") ?(proxy = SystemProxy) ?tmpdir args =
  let args = safe_args @ args_of_proxy proxy @ args in
  { curl = curl; args = args; tmpdir = tmpdir }

let run { curl; args; tmpdir } =
  let config_file, chan = Filename.open_temp_file ?temp_dir:tmpdir
    "guestfscurl" ".conf" in
  List.iter (
    function
    | name, None -> fprintf chan "%s\n" name
    | name, Some value ->
      fprintf chan "%s = \"" name;
      (* Write the quoted value.  See 'curl' man page for what is
       * allowed here.
       *)
      let len = String.length value in
      for i = 0 to len-1 do
        match value.[i] with
        | '\\' -> output_string chan "\\\\"
        | '"' -> output_string chan "\\\""
        | '\t' -> output_string chan "\\t"
        | '\n' -> output_string chan "\\n"
        | '\r' -> output_string chan "\\r"
        | '\x0b' -> output_string chan "\\v"
        | c -> output_char chan c
      done;
      fprintf chan "\"\n"
  ) args;
  close_out chan;

  let cmd = sprintf "%s -q --config %s" (quote curl) (quote config_file) in
  let lines = external_command ~echo_cmd:false cmd in
  Unix.unlink config_file;
  lines

let to_string { curl; args } =
  let b = Buffer.create 128 in
  bprintf b "%s -q" (quote curl);
  List.iter (
    function
    | name, None -> bprintf b " --%s" name
    (* Don't print passwords in the debug output. *)
    | "user", Some _ -> bprintf b " --user <hidden>"
    | name, Some value -> bprintf b " --%s %s" name (quote value)
  ) args;
  bprintf b "\n";
  Buffer.contents b

let print chan t = output_string chan (to_string t)
