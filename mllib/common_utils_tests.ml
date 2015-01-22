(* virt-resize
 * Copyright (C) 2011 Red Hat Inc.
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

(* This file tests the Common_utils module. *)

open OUnit
open Common_utils

let prog = "common_utils_tests"

(* Utils. *)
let assert_equal_string = assert_equal ~printer:(fun x -> x)
let assert_equal_int = assert_equal ~printer:(fun x -> string_of_int x)
let assert_equal_int64 = assert_equal ~printer:(fun x -> Int64.to_string x)

(* Test Common_utils.int_of_le32 and Common_utils.le32_of_int. *)
let test_le32 () =
  assert_equal_int64 0x20406080L (int_of_le32 "\x80\x60\x40\x20");
  assert_equal_string "\x80\x60\x40\x20" (le32_of_int 0x20406080L)

(* Test Common_utils.parse_size. *)
let test_parse_resize () =
  (* For absolute sizes, oldsize is ignored. *)
  assert_equal_int64 100_L (parse_resize ~prog 100_L "100b");
  assert_equal_int64 100_L (parse_resize ~prog 1000_L "100b");
  assert_equal_int64 100_L (parse_resize ~prog 10000_L "100b");
  assert_equal_int64 102400_L (parse_resize ~prog 100_L "100K");
  (* Fractions are always rounded down. *)
  assert_equal_int64 1126_L (parse_resize ~prog 100_L "1.1K");
  assert_equal_int64 104962457_L (parse_resize ~prog 100_L "100.1M");
  assert_equal_int64 132499741081_L (parse_resize ~prog 100_L "123.4G");

  (* oldsize +/- a constant. *)
  assert_equal_int64 101_L (parse_resize ~prog 100_L "+1b");
  assert_equal_int64 98_L (parse_resize ~prog 100_L "-2b");
  assert_equal_int64 1124_L (parse_resize ~prog 100_L "+1K");
  assert_equal_int64 0_L (parse_resize ~prog 1024_L "-1K");
  assert_equal_int64 0_L (parse_resize ~prog 1126_L "-1.1K");
  assert_equal_int64 1154457_L (parse_resize ~prog 1024_L "+1.1M");
  assert_equal_int64 107374182_L (parse_resize ~prog 132499741081_L "-123.3G");

  (* oldsize +/- a percentage. *)
  assert_equal_int64 101_L (parse_resize ~prog 100_L "+1%");
  assert_equal_int64 99_L (parse_resize ~prog 100_L "-1%");
  assert_equal_int64 101000_L (parse_resize ~prog 100000_L "+1%");
  assert_equal_int64 99000_L (parse_resize ~prog 100000_L "-1%");
  assert_equal_int64 150000_L (parse_resize ~prog 100000_L "+50%");
  assert_equal_int64 50000_L (parse_resize ~prog 100000_L "-50%");
  assert_equal_int64 200000_L (parse_resize ~prog 100000_L "+100%");
  assert_equal_int64 0_L (parse_resize ~prog 100000_L "-100%");
  assert_equal_int64 300000_L (parse_resize ~prog 100000_L "+200%");
  assert_equal_int64 400000_L (parse_resize ~prog 100000_L "+300%");

  (* Implementation rounds numbers so that only a single digit after
   * the decimal point is significant.
   *)
  assert_equal_int64 101100_L (parse_resize ~prog 100000_L "+1.1%");
  assert_equal_int64 101100_L (parse_resize ~prog 100000_L "+1.12%")

(* Test Common_utils.human_size. *)
let test_human_size () =
  assert_equal_string "100" (human_size 100_L);
  assert_equal_string "-100" (human_size (-100_L));
  assert_equal_string "1.0K" (human_size 1024_L);
  assert_equal_string "-1.0K" (human_size (-1024_L));
  assert_equal_string "1.1K" (human_size 1126_L);
  assert_equal_string "-1.1K" (human_size (-1126_L));
  assert_equal_string "1.3M" (human_size 1363149_L);
  assert_equal_string "-1.3M" (human_size (-1363149_L));
  assert_equal_string "3.4G" (human_size 3650722201_L);
  assert_equal_string "-3.4G" (human_size (-3650722201_L))

(* Test Common_utils.string_prefix. *)
let test_string_prefix () =
  assert_bool "string_prefix,," (string_prefix "" "");
  assert_bool "string_prefix,foo," (string_prefix "foo" "");
  assert_bool "string_prefix,foo,foo" (string_prefix "foo" "foo");
  assert_bool "string_prefix,foo123,foo" (string_prefix "foo123" "foo");
  assert_bool "not (string_prefix,,foo" (not (string_prefix "" "foo"))

(* Test Common_utils.string_suffix. *)
let test_string_suffix () =
  assert_bool "string_suffix,," (string_suffix "" "");
  assert_bool "string_suffix,foo," (string_suffix "foo" "");
  assert_bool "string_suffix,foo,foo" (string_suffix "foo" "foo");
  assert_bool "string_suffix,123foo,foo" (string_suffix "123foo" "foo");
  assert_bool "not string_suffix,,foo" (not (string_suffix "" "foo"))

(* Test Common_utils.string_find. *)
let test_string_find () =
  assert_equal_int 0 (string_find "" "");
  assert_equal_int 0 (string_find "foo" "");
  assert_equal_int 1 (string_find "foo" "o");
  assert_equal_int 3 (string_find "foobar" "bar");
  assert_equal_int (-1) (string_find "" "baz");
  assert_equal_int (-1) (string_find "foobar" "baz")

(* Suites declaration. *)
let suite =
  TestList ([
    "numeric" >::: [
      "le32" >:: test_le32;
    ];
    "sizes" >::: [
      "parse_resize" >:: test_parse_resize;
      "human_size" >:: test_human_size;
    ];
    "strings" >::: [
      "prefix" >:: test_string_prefix;
      "suffix" >:: test_string_suffix;
      "find" >:: test_string_find;
    ];
  ])

let _ =
  run_test_tt_main suite

let () =
  Printf.fprintf stderr "\n"
