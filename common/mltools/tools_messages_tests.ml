(*
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

(* Test the message output for tools of the module Tools_utils.
 * The tests are controlled by the test-tools-messages.sh script.
 *)

open Printf

open Std_utils
open Tools_utils
open Getopt.OptionName

let is_error = ref false

let args = [
  [ L "error" ], Getopt.Set is_error, "Only print the error";
]
let usage_msg = sprintf "%s: test the message outputs" prog

let opthandle = create_standard_options args ~machine_readable:true usage_msg
let () =
  Getopt.parse opthandle.getopt;

  if !is_error then
    error "Error!";

  message "Starting";
  info "An information message";
  warning "Warning: message here";
  message "Finishing"
