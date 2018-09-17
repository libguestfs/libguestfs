(*
 * Copyright (C) 2018 Red Hat Inc.
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

(* Test the --machine-readable functionality of the module Tools_utils.
 * The tests are controlled by the test-machine_readable.sh script.
 *)

open Printf

open Std_utils
open Tools_utils
open Getopt.OptionName

let usage_msg = sprintf "%s: test the --machine-readable functionality" prog

let opthandle = create_standard_options [] ~machine_readable:true usage_msg
let () =
  Getopt.parse opthandle.getopt;

  print_endline "on-stdout";
  prerr_endline "on-stderr";

  match machine_readable () with
  | Some { pr } ->
    pr "machine-readable\n"
  | None -> ()
