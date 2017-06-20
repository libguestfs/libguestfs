(* Common utilities for OCaml tools in libguestfs.
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

(* This file tests the Common_utils module. *)

open OUnit2
open Common_utils

(* Utils. *)
let assert_equal_string = assert_equal ~printer:(fun x -> x)
let assert_equal_int = assert_equal ~printer:(fun x -> string_of_int x)
let assert_equal_int64 = assert_equal ~printer:(fun x -> Int64.to_string x)
let assert_equal_stringlist = assert_equal ~printer:(fun x -> "(" ^ (String.escaped (String.concat "," x)) ^ ")")
let assert_equal_intlist = assert_equal ~printer:(fun x -> "(" ^ (String.concat ";" (List.map string_of_int x)) ^ ")")

let test_subdirectory ctx =
  assert_equal_string "" (subdirectory "/foo" "/foo");
  assert_equal_string "" (subdirectory "/foo" "/foo/");
  assert_equal_string "bar" (subdirectory "/foo" "/foo/bar");
  assert_equal_string "bar/baz" (subdirectory "/foo" "/foo/bar/baz")

(* Test Common_utils.int_of_le32 and Common_utils.le32_of_int. *)
let test_le32 ctx =
  assert_equal_int64 0x20406080L (int_of_le32 "\x80\x60\x40\x20");
  assert_equal_string "\x80\x60\x40\x20" (le32_of_int 0x20406080L)

(* Test Common_utils.parse_size. *)
let test_parse_resize ctx =
  (* For absolute sizes, oldsize is ignored. *)
  assert_equal_int64 100_L (parse_resize 100_L "100b");
  assert_equal_int64 100_L (parse_resize 1000_L "100b");
  assert_equal_int64 100_L (parse_resize 10000_L "100b");
  assert_equal_int64 102400_L (parse_resize 100_L "100K");
  (* Fractions are always rounded down. *)
  assert_equal_int64 1126_L (parse_resize 100_L "1.1K");
  assert_equal_int64 104962457_L (parse_resize 100_L "100.1M");
  assert_equal_int64 132499741081_L (parse_resize 100_L "123.4G");

  (* oldsize +/- a constant. *)
  assert_equal_int64 101_L (parse_resize 100_L "+1b");
  assert_equal_int64 98_L (parse_resize 100_L "-2b");
  assert_equal_int64 1124_L (parse_resize 100_L "+1K");
  assert_equal_int64 0_L (parse_resize 1024_L "-1K");
  assert_equal_int64 0_L (parse_resize 1126_L "-1.1K");
  assert_equal_int64 1154457_L (parse_resize 1024_L "+1.1M");
  assert_equal_int64 107374182_L (parse_resize 132499741081_L "-123.3G");

  (* oldsize +/- a percentage. *)
  assert_equal_int64 101_L (parse_resize 100_L "+1%");
  assert_equal_int64 99_L (parse_resize 100_L "-1%");
  assert_equal_int64 101000_L (parse_resize 100000_L "+1%");
  assert_equal_int64 99000_L (parse_resize 100000_L "-1%");
  assert_equal_int64 150000_L (parse_resize 100000_L "+50%");
  assert_equal_int64 50000_L (parse_resize 100000_L "-50%");
  assert_equal_int64 200000_L (parse_resize 100000_L "+100%");
  assert_equal_int64 0_L (parse_resize 100000_L "-100%");
  assert_equal_int64 300000_L (parse_resize 100000_L "+200%");
  assert_equal_int64 400000_L (parse_resize 100000_L "+300%");

  (* Implementation rounds numbers so that only a single digit after
   * the decimal point is significant.
   *)
  assert_equal_int64 101100_L (parse_resize 100000_L "+1.1%");
  assert_equal_int64 101100_L (parse_resize 100000_L "+1.12%")

(* Test Common_utils.human_size. *)
let test_human_size ctx =
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

(* Test Common_utils.String.is_prefix. *)
let test_string_is_prefix ctx =
  assert_bool "String.is_prefix,," (String.is_prefix "" "");
  assert_bool "String.is_prefix,foo," (String.is_prefix "foo" "");
  assert_bool "String.is_prefix,foo,foo" (String.is_prefix "foo" "foo");
  assert_bool "String.is_prefix,foo123,foo" (String.is_prefix "foo123" "foo");
  assert_bool "not (String.is_prefix,,foo" (not (String.is_prefix "" "foo"))

(* Test Common_utils.String.is_suffix. *)
let test_string_is_suffix ctx =
  assert_bool "String.is_suffix,," (String.is_suffix "" "");
  assert_bool "String.is_suffix,foo," (String.is_suffix "foo" "");
  assert_bool "String.is_suffix,foo,foo" (String.is_suffix "foo" "foo");
  assert_bool "String.is_suffix,123foo,foo" (String.is_suffix "123foo" "foo");
  assert_bool "not String.is_suffix,,foo" (not (String.is_suffix "" "foo"))

(* Test Common_utils.String.find. *)
let test_string_find ctx =
  assert_equal_int 0 (String.find "" "");
  assert_equal_int 0 (String.find "foo" "");
  assert_equal_int 1 (String.find "foo" "o");
  assert_equal_int 3 (String.find "foobar" "bar");
  assert_equal_int (-1) (String.find "" "baz");
  assert_equal_int (-1) (String.find "foobar" "baz")

(* Test Common_utils.String.lines_split. *)
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

(* Test Common_utils.run_command. *)
let test_run_command ctx =
  assert_equal_int 0 (run_command ["true"]);
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_command ["echo"; "this is a test"] ~stdout_chan:(Unix.descr_of_out_channel chan) in
    assert_equal_int 0 res;
    let content = read_whole_file tmpfile in
    assert_equal_string "this is a test\n" content
  end;
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_command ["ls"; "/this-directory-is-unlikely-to-exist"] ~stderr_chan:(Unix.descr_of_out_channel chan) in
    assert_equal_int 2 res;
    let content = read_whole_file tmpfile in
    assert_bool "test_run_commands/not-existing/content" (String.length content > 0)
  end;
  ()

(* Test Common_utils.run_commands. *)
let test_run_commands ctx =
  begin
    let res = run_commands [] in
    assert_equal_intlist [] res
  end;
  begin
    let res = run_commands [(["true"], None, None)] in
    assert_equal_intlist [0] res
  end;
  begin
    let res = run_commands [(["true"], None, None); (["false"], None, None)] in
    assert_equal_intlist [0; 1] res
  end;
  begin
    let res = run_commands [(["this-command-does-not-really-exist"], None, None)] in
    assert_equal_intlist [127] res
  end;
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_commands [(["echo"; "this is a test"], Some (Unix.descr_of_out_channel chan), None)] in
    assert_equal_intlist [0] res;
    let content = read_whole_file tmpfile in
    assert_equal_string "this is a test\n" content
  end;
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_commands [(["ls"; "/this-directory-is-unlikely-to-exist"], None, Some (Unix.descr_of_out_channel chan))] in
    assert_equal_intlist [2] res;
    let content = read_whole_file tmpfile in
    assert_bool "test_run_commands/not-existing/content" (String.length content > 0)
  end;
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_commands [(["echo"; "this is a test"], Some (Unix.descr_of_out_channel chan), None); (["false"], None, None)] in
    assert_equal_intlist [0; 1] res;
    let content = read_whole_file tmpfile in
    assert_equal_string "this is a test\n" content
  end;
  begin
    let tmpfile, chan = bracket_tmpfile ctx in
    let res = run_commands [(["this-command-does-not-really-exist"], None, None); (["echo"; "this is a test"], Some (Unix.descr_of_out_channel chan), None)] in
    assert_equal_intlist [127; 0] res;
    let content = read_whole_file tmpfile in
    assert_equal_string "this is a test\n" content
  end;
  ()

(* Suites declaration. *)
let suite =
  "mllib Common_utils" >:::
    [
      "subdirectory" >:: test_subdirectory;
      "numeric.le32" >:: test_le32;
      "sizes.parse_resize" >:: test_parse_resize;
      "sizes.human_size" >:: test_human_size;
      "strings.is_prefix" >:: test_string_is_prefix;
      "strings.is_suffix" >:: test_string_is_suffix;
      "strings.find" >:: test_string_find;
      "strings.lines_split" >:: test_string_lines_split;
      "run_command" >:: test_run_command;
      "run_commands" >:: test_run_commands;
    ]

let () =
  run_test_tt_main suite
