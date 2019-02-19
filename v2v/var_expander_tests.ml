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
open OUnit

open Std_utils

let assert_equal_string = assert_equal ~printer:identity
let assert_equal_stringlist = assert_equal ~printer:(fun x -> "(" ^ (String.escaped (String.concat "," x)) ^ ")")

let replace_none_fn _ = None
let replace_empty_fn _ = Some ""

let test_no_replacement () =
  assert_equal_string "" (Var_expander.replace_fn "" replace_none_fn);
  assert_equal_string "x" (Var_expander.replace_fn "x" replace_none_fn);
  assert_equal_string "%{}" (Var_expander.replace_fn "%{}" replace_none_fn);
  assert_equal_string "%{EMPTY}" (Var_expander.replace_fn "%{EMPTY}" replace_none_fn);
  assert_equal_string "%{EMPTY} %{no}" (Var_expander.replace_fn "%{EMPTY} %{no}" replace_none_fn);
  assert_equal_string "a %{EMPTY} b" (Var_expander.replace_fn "a %{EMPTY} b" replace_none_fn);
  ()

let test_replacements () =
  assert_equal_string "" (Var_expander.replace_fn "%{EMPTY}" replace_empty_fn);
  assert_equal_string "x " (Var_expander.replace_fn "x %{EMPTY}" replace_empty_fn);
  assert_equal_string "xy" (Var_expander.replace_fn "x%{EMPTY}y" replace_empty_fn);
  assert_equal_string "x<->y" (Var_expander.replace_fn "x%{FOO}y" (function | "FOO" -> Some "<->" | _ -> None));
  assert_equal_string "a x b" (Var_expander.replace_fn "a %{FOO} b" (function | "FOO" -> Some "x" | _ -> None));
  assert_equal_string "%{FOO} x" (Var_expander.replace_fn "%{FOO} %{BAR}" (function | "BAR" -> Some "x" | _ -> None));
  assert_equal_string "%{FOO}" (Var_expander.replace_fn "%{BAR}" (function | "BAR" -> Some "%{FOO}" | _ -> None));
  assert_equal_string "%{FOO} x" (Var_expander.replace_fn "%{BAR} %{FOO}" (function | "BAR" -> Some "%{FOO}" | "FOO" -> Some "x" | _ -> None));
  begin
    let str = "%{INDEX}, %{INDEX}, %{INDEX}" in
    let index = ref 0 in
    let fn = function
      | "INDEX" ->
        incr index;
        Some (string_of_int !index)
      | _ -> None
    in
    assert_equal_string "1, 2, 3" (Var_expander.replace_fn str fn)
  end;
  ()

let test_escape () =
  assert_equal_string "%%{FOO}" (Var_expander.replace_fn "%%{FOO}" replace_empty_fn);
  assert_equal_string "x %%{FOO} x" (Var_expander.replace_fn "%{FOO} %%{FOO} %{FOO}" (function | "FOO" -> Some "x" | _ -> None));
  ()

let test_list () =
  assert_equal_string "x %{NONE}" (Var_expander.replace_list "%{FOO} %{NONE}" [("FOO", "x")]);
  ()

let test_scan_variables () =
  let assert_invalid_variable var =
    let str = "%{" ^ var ^ "}" in
    assert_raises (Var_expander.Invalid_variable var)
                  (fun () -> Var_expander.scan_variables str)
  in
  assert_equal_stringlist [] (Var_expander.scan_variables "");
  assert_equal_stringlist [] (Var_expander.scan_variables "foo");
  assert_equal_stringlist ["FOO"] (Var_expander.scan_variables "%{FOO}");
  assert_equal_stringlist ["FOO"; "BAR"] (Var_expander.scan_variables "%{FOO} %{BAR}");
  assert_equal_stringlist ["FOO"; "BAR"] (Var_expander.scan_variables "%{FOO} %{BAR} %{FOO}");
  assert_equal_stringlist ["FOO"; "BAR"] (Var_expander.scan_variables "%{FOO} %%{ESCAPED} %{BAR}");
  assert_invalid_variable "FOO/BAR";
  ()

let test_errors () =
  let assert_invalid_variable var =
    let str = "%{" ^ var ^ "}" in
    assert_raises (Var_expander.Invalid_variable var)
                  (fun () -> Var_expander.replace_fn str replace_none_fn)
  in
  assert_invalid_variable "FOO/BAR";
  assert_invalid_variable "FOO:BAR";
  assert_invalid_variable "FOO(BAR";
  assert_invalid_variable "FOO)BAR";
  assert_invalid_variable "FOO@BAR";
  ()

(* Suites declaration. *)
let suite =
  TestList ([
    "basic" >::: [
      "no_replacement" >:: test_no_replacement;
      "replacements" >:: test_replacements;
      "escape" >:: test_escape;
      "list" >:: test_list;
      "scan_variables" >:: test_scan_variables;
      "errors" >:: test_errors;
    ];
  ])

let () =
  ignore (run_test_tt_main suite);
  Printf.fprintf stderr "\n"
