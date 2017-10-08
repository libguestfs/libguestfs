(* mllib
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

(* Test the Getopt module.  The tests are controlled by the
 * test-getopt.sh script.
 *)

open Printf

open Std_utils
open Tools_utils
open Getopt.OptionName

let adds = ref []
let add_string = List.push_back adds

let anons = ref []
let anon_fun = List.push_back anons

let ints = ref []
let add_int = List.push_back ints

let clear_flag = ref true
let set_flag = ref false
let si = ref 42
let ss = ref "not set"

let argspec = [
  [ S 'a'; L"add" ],  Getopt.String ("string", add_string), "Add string";
  [ S 'c'; L"clear" ], Getopt.Clear clear_flag, "Clear flag";
  [ S 'i'; L"int" ], Getopt.Int ("int", add_int), "Add int";
  [ M"ii"; L"set-int" ], Getopt.Set_int ("int", si), "Set int";
  [ M"is"; L"set-string"], Getopt.Set_string ("string", ss), "Set string";
  [ S 't'; L"set" ], Getopt.Set set_flag, "Set flag";
]

let usage_msg = sprintf "%s: test the Getopt parser" prog

let opthandle = create_standard_options argspec ~anon_fun usage_msg
let () =
  Getopt.parse opthandle;

  (* Implicit settings. *)
  printf "trace = %b\n" (trace ());
  printf "verbose = %b\n" (verbose ());

  (* Print the results. *)
  printf "adds = [%s]\n" (String.concat ", " !adds);
  printf "anons = [%s]\n" (String.concat ", " !anons);
  printf "ints = [%s]\n" (String.concat ", " (List.map string_of_int !ints));
  printf "clear_flag = %b\n" !clear_flag;
  printf "set_flag = %b\n" !set_flag;
  printf "set_int = %d\n" !si;
  printf "set_string = %s\n" !ss
