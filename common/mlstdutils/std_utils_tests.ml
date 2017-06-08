(* Utilities for OCaml tools in libguestfs.
 * Copyright (C) 2011-2017 Red Hat Inc.
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

(* This file tests the Std_utils module. *)

open OUnit2
open Std_utils

(* Utils. *)
let assert_equal_string = assert_equal ~printer:(fun x -> x)
let assert_equal_int = assert_equal ~printer:(fun x -> string_of_int x)
let assert_equal_int64 = assert_equal ~printer:(fun x -> Int64.to_string x)
let assert_equal_stringlist = assert_equal ~printer:(fun x -> "(" ^ (String.escaped (String.concat "," x)) ^ ")")

let test_subdirectory ctx =
  assert_equal_string "" (subdirectory "/foo" "/foo");
  assert_equal_string "" (subdirectory "/foo" "/foo/");
  assert_equal_string "bar" (subdirectory "/foo" "/foo/bar");
  assert_equal_string "bar/baz" (subdirectory "/foo" "/foo/bar/baz")

(* Test Common_utils.int_of_le32 and Common_utils.le32_of_int. *)
let test_le32 ctx =
  assert_equal_int64 0x20406080L (int_of_le32 "\x80\x60\x40\x20");
  assert_equal_string "\x80\x60\x40\x20" (le32_of_int 0x20406080L)

(* Test Std_utils.String.is_prefix. *)
let test_string_is_prefix ctx =
  assert_bool "String.is_prefix,," (String.is_prefix "" "");
  assert_bool "String.is_prefix,foo," (String.is_prefix "foo" "");
  assert_bool "String.is_prefix,foo,foo" (String.is_prefix "foo" "foo");
  assert_bool "String.is_prefix,foo123,foo" (String.is_prefix "foo123" "foo");
  assert_bool "not (String.is_prefix,,foo" (not (String.is_prefix "" "foo"))

(* Test Std_utils.String.is_suffix. *)
let test_string_is_suffix ctx =
  assert_bool "String.is_suffix,," (String.is_suffix "" "");
  assert_bool "String.is_suffix,foo," (String.is_suffix "foo" "");
  assert_bool "String.is_suffix,foo,foo" (String.is_suffix "foo" "foo");
  assert_bool "String.is_suffix,123foo,foo" (String.is_suffix "123foo" "foo");
  assert_bool "not String.is_suffix,,foo" (not (String.is_suffix "" "foo"))

(* Test Std_utils.String.find. *)
let test_string_find ctx =
  assert_equal_int 0 (String.find "" "");
  assert_equal_int 0 (String.find "foo" "");
  assert_equal_int 1 (String.find "foo" "o");
  assert_equal_int 3 (String.find "foobar" "bar");
  assert_equal_int (-1) (String.find "" "baz");
  assert_equal_int (-1) (String.find "foobar" "baz")

(* Test Std_utils.String.lines_split. *)
let test_string_lines_split ctx =
  assert_equal_stringlist [""] (String.lines_split "");
  assert_equal_stringlist ["A"] (String.lines_split "A");
  assert_equal_stringlist ["A"; ""] (String.lines_split "A\n");
  assert_equal_stringlist ["A"; "B"] (String.lines_split "A\nB");
  assert_equal_stringlist ["A"; "B"; "C"] (String.lines_split "A\nB\nC");
  assert_equal_stringlist ["A"; "B"; "C"; "D"] (String.lines_split "A\nB\nC\nD");
  assert_equal_stringlist ["A\n"] (String.lines_split "A\\");
  assert_equal_stringlist ["A\nB"] (String.lines_split "A\\\nB");
  assert_equal_stringlist ["A"; "B\nC"] (String.lines_split "A\nB\\\nC");
  assert_equal_stringlist ["A"; "B\nC"; "D"] (String.lines_split "A\nB\\\nC\nD");
  assert_equal_stringlist ["A"; "B\nC\nD"] (String.lines_split "A\nB\\\nC\\\nD");
  assert_equal_stringlist ["A\nB"; ""] (String.lines_split "A\\\nB\n");
  assert_equal_stringlist ["A\nB\n"] (String.lines_split "A\\\nB\\\n")

(* Suites declaration. *)
let suite =
  "mllib Std_utils" >:::
    [
      "subdirectory" >:: test_subdirectory;
      "numeric.le32" >:: test_le32;
      "strings.is_prefix" >:: test_string_is_prefix;
      "strings.is_suffix" >:: test_string_is_suffix;
      "strings.find" >:: test_string_find;
      "strings.lines_split" >:: test_string_lines_split;
    ]

let () =
  run_test_tt_main suite
