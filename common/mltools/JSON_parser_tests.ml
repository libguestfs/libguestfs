(* virt-builder
 * Copyright (C) 2015 Red Hat Inc.
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

(* This file tests the JSON_parser module. *)

open OUnit2
open JSON_parser

(* Utils. *)
let assert_equal_string = assert_equal ~printer:(fun x -> x)
let assert_equal_int = assert_equal ~printer:(fun x -> string_of_int x)
let assert_equal_int64 = assert_equal ~printer:(fun x -> Int64.to_string x)
let assert_equal_bool = assert_equal ~printer:(fun x -> string_of_bool x)

let string_of_json_parser_val_type = function
  | JSON_parser_null -> "null"
  | JSON_parser_string _ -> "string"
  | JSON_parser_number _ -> "number"
  | JSON_parser_double _ -> "float"
  | JSON_parser_object _ -> "object"
  | JSON_parser_array _ -> "array"
  | JSON_parser_bool _ -> "bool"
let type_mismatch_string exp value =
  Printf.sprintf "value is not %s but %s" exp (string_of_json_parser_val_type value)

let assert_raises_invalid_argument str =
  (* Replace the Invalid_argument string with a fixed one, just to check
   * whether the exception has been raised.
   *)
  let mock = "parse_error" in
  let wrapped_tree_parse str =
    try json_parser_tree_parse str
    with Invalid_argument _ -> raise (Invalid_argument mock) in
  assert_raises (Invalid_argument mock) (fun () -> wrapped_tree_parse str)
let assert_raises_nested str =
  let err = "too many levels of object/array nesting" in
  assert_raises (Invalid_argument err) (fun () -> json_parser_tree_parse str)

let assert_is_object value =
  assert_bool
    (type_mismatch_string "object" value)
    (match value with | JSON_parser_object _ -> true | _ -> false)
let assert_is_string exp = function
  | JSON_parser_string s -> assert_equal_string exp s
  | _ as v -> assert_failure (type_mismatch_string "string" v)
let assert_is_number exp = function
  | JSON_parser_number n -> assert_equal_int64 exp n
  | JSON_parser_double d -> assert_equal_int64 exp (Int64.of_float d)
  | _ as v -> assert_failure (type_mismatch_string "number/double" v)
let assert_is_array value =
  assert_bool
    (type_mismatch_string "array" value)
    (match value with | JSON_parser_array _ -> true | _ -> false)
let assert_is_bool exp = function
  | JSON_parser_bool b -> assert_equal_bool exp b
  | _ as v -> assert_failure (type_mismatch_string "bool" v)

let get_object_list = function
  | JSON_parser_object x -> x
  | _ as v -> assert_failure (type_mismatch_string "object" v)
let get_array = function
  | JSON_parser_array x -> x
  | _ as v -> assert_failure (type_mismatch_string "array" v)


let test_tree_parse_invalid ctx =
  assert_raises_invalid_argument "";
  assert_raises_invalid_argument "invalid";
  assert_raises_invalid_argument ":5";

  (* Nested objects/arrays. *)
  let str = "[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]" in
  assert_raises_nested str;
  let str = "{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":5}}}}}}}}}}}}}}}}}}}}}" in
  assert_raises_nested str

let test_tree_parse_basic ctx =
  let value = json_parser_tree_parse "{}" in
  assert_is_object value;

  let value = json_parser_tree_parse "\"foo\"" in
  assert_is_string "foo" value;

  let value = json_parser_tree_parse "[]" in
  assert_is_array value

let test_tree_parse_inspect ctx =
  let value = json_parser_tree_parse "{\"foo\":5}" in
  let l = get_object_list value in
  assert_equal_int 1 (Array.length l);
  assert_equal_string "foo" (fst (l.(0)));
  assert_is_number 5_L (snd (l.(0)));

  let value = json_parser_tree_parse "[\"foo\", true]" in
  let a = get_array value in
  assert_equal_int 2 (Array.length a);
  assert_is_string "foo" (a.(0));
  assert_is_bool true (a.(1));

  let value = json_parser_tree_parse "{\"foo\":[false, {}, 10], \"second\":2}" in
  let l = get_object_list value in
  assert_equal_int 2 (Array.length l);
  assert_equal_string "foo" (fst (l.(0)));
  let a = get_array (snd (l.(0))) in
  assert_equal_int 3 (Array.length a);
  assert_is_bool false (a.(0));
  assert_is_object (a.(1));
  assert_is_number 10_L (a.(2));
  assert_equal_string "second" (fst (l.(1)));
  assert_is_number 2_L (snd (l.(1)))

(* Suites declaration. *)
let suite =
  "mltools JSON_parser" >:::
    [
      "tree_parse.invalid" >:: test_tree_parse_invalid;
      "tree_parse.basic" >:: test_tree_parse_basic;
      "tree_parse.inspect" >:: test_tree_parse_inspect;
    ]

let () =
  run_test_tt_main suite
