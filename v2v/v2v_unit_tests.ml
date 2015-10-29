(* virt-v2v
 * Copyright (C) 2011-2015 Red Hat Inc.
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

(* This file tests individual virt-v2v functions. *)

open OUnit2
open Types

external identity : 'a -> 'a = "%identity"

let test_get_ostype ctx =
  let i = { i_type = ""; i_distro = ""; i_arch = "";
            i_major_version = 0; i_minor_version = 0;
            i_root = ""; i_package_format = ""; i_package_management = "";
            i_product_name = ""; i_product_variant = ""; i_mountpoints = [];
            i_apps = []; i_apps_map = StringMap.empty; i_uefi = false } in
  let printer = identity in
  assert_equal ~printer "RHEL6"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 6;
                                        i_minor_version = 0;
                                        i_arch = "i386" });
  assert_equal ~printer "RHEL6x64"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 6;
                                        i_minor_version = 0;
                                        i_arch = "x86_64" });
  assert_equal ~printer "rhel_7x64"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 7;
                                        i_minor_version = 0;
                                        i_arch = "x86_64" });
  assert_equal ~printer "Windows7"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 1;
                                        i_product_variant = "Client";
                                        i_arch = "i386" });
  assert_equal ~printer "Windows7x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 1;
                                        i_product_variant = "Client";
                                        i_arch = "x86_64" });
  assert_equal ~printer "windows_8"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Client";
                                        i_arch = "i386" });
  assert_equal ~printer "windows_8x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Client";
                                        i_arch = "x86_64" });
  assert_equal ~printer "windows_2012x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Server";
                                        i_arch = "x86_64" });
  assert_equal ~printer "windows_2012R2x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 3;
                                        i_product_variant = "Server";
                                        i_arch = "x86_64" })

let test_drive_name ctx =
  let printer = identity in
  assert_equal ~printer "a" (Utils.drive_name 0);
  assert_equal ~printer "z" (Utils.drive_name 25);
  assert_equal ~printer "aa" (Utils.drive_name 26);
  assert_equal ~printer "ab" (Utils.drive_name 27);
  assert_equal ~printer "az" (Utils.drive_name 51);
  assert_equal ~printer "ba" (Utils.drive_name 52);
  assert_equal ~printer "zz" (Utils.drive_name 701);
  assert_equal ~printer "aaa" (Utils.drive_name 702);
  assert_equal ~printer "zzz" (Utils.drive_name 18277)

let test_drive_index ctx =
  let printer = string_of_int in
  assert_equal ~printer 0 (Utils.drive_index "a");
  assert_equal ~printer 25 (Utils.drive_index "z");
  assert_equal ~printer 26 (Utils.drive_index "aa");
  assert_equal ~printer 27 (Utils.drive_index "ab");
  assert_equal ~printer 51 (Utils.drive_index "az");
  assert_equal ~printer 52 (Utils.drive_index "ba");
  assert_equal ~printer 701 (Utils.drive_index "zz");
  assert_equal ~printer 702 (Utils.drive_index "aaa");
  assert_equal ~printer 18277 (Utils.drive_index "zzz");
  let exn = Invalid_argument "drive_index: invalid parameter" in
  assert_raises exn (fun () -> Utils.drive_index "");
  assert_raises exn (fun () -> Utils.drive_index "abc123");
  assert_raises exn (fun () -> Utils.drive_index "123");
  assert_raises exn (fun () -> Utils.drive_index "Z");
  assert_raises exn (fun () -> Utils.drive_index "aB")

(* Suites declaration. *)
let suite =
  "virt-v2v" >:::
    [
      "OVF.get_ostype" >:: test_get_ostype;
      "Utils.drive_name" >:: test_drive_name;
      "Utils.drive_index" >:: test_drive_index;
    ]

let () =
  run_test_tt_main suite
