(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

open Common_utils

type curl_args = (string * string option) list

let run curl_args =
  let config_file, chan = Filename.open_temp_file "v2vcurl" ".conf" in
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
  ) curl_args;
  close_out chan;

  let cmd = sprintf "curl -q --config %s" (Filename.quote config_file) in
  let lines = external_command cmd in
  Unix.unlink config_file;
  lines

let print_curl_command chan curl_args =
  fprintf chan "curl -q";
  List.iter (
    function
    | name, None -> fprintf chan " --%s" name
    (* Don't print passwords in the debug output. *)
    | "user", Some _ -> fprintf chan " --user <hidden>"
    | name, Some value -> fprintf chan " --%s %s" name (Filename.quote value)
  ) curl_args;
  fprintf chan "\n";
