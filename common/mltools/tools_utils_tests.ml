(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2011-2018 Red Hat Inc.
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

(* This file tests the Tools_utils module. *)

open OUnit2

open Std_utils
open Tools_utils

(* Utils. *)
let assert_equal_string = assert_equal ~printer:(fun x -> x)
let assert_equal_int = assert_equal ~printer:(fun x -> string_of_int x)
let assert_equal_int64 = assert_equal ~printer:(fun x -> Int64.to_string x)
let assert_equal_intlist = assert_equal ~printer:(fun x -> "(" ^ (String.concat ";" (List.map string_of_int x)) ^ ")")

(* Test Tools_utils.parse_size and Tools_utils.parse_resize. *)
let test_parse_resize ctx =
  assert_equal_int64 1_L (parse_size "1b");
  assert_equal_int64 10_L (parse_size "10b");
  assert_equal_int64 1024_L (parse_size "1K");
  assert_equal_int64 102400_L (parse_size "100K");
  (* Fractions are always rounded down. *)
  assert_equal_int64 1153433_L (parse_size "1.1M");
  assert_equal_int64 1202590842_L (parse_size "1.12G");

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

(* Test Tools_utils.human_size. *)
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

(* Test Tools_utils.run_command. *)
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

(* Test Tools_utils.run_commands. *)
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
  "mltools Tools_utils" >:::
    [
      "sizes.parse_resize" >:: test_parse_resize;
      "sizes.human_size" >:: test_human_size;
      "run_command" >:: test_run_command;
      "run_commands" >:: test_run_commands;
    ]

let () =
  run_test_tt_main suite
