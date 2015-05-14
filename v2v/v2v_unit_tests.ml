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
  assert_equal ~printer:identity "RHEL6"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 6;
                                        i_minor_version = 0;
                                        i_arch = "i386" });
  assert_equal ~printer:identity "RHEL6x64"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 6;
                                        i_minor_version = 0;
                                        i_arch = "x86_64" });
  assert_equal ~printer:identity "rhel_7x64"
               (OVF.get_ostype { i with i_type = "linux"; i_distro = "rhel";
                                        i_major_version = 7;
                                        i_minor_version = 0;
                                        i_arch = "x86_64" });
  assert_equal ~printer:identity "Windows7"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 1;
                                        i_product_variant = "Client";
                                        i_arch = "i386" });
  assert_equal ~printer:identity "Windows7x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 1;
                                        i_product_variant = "Client";
                                        i_arch = "x86_64" });
  assert_equal ~printer:identity "windows_8"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Client";
                                        i_arch = "i386" });
  assert_equal ~printer:identity "windows_8x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Client";
                                        i_arch = "x86_64" });
  assert_equal ~printer:identity "windows_2012x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 2;
                                        i_product_variant = "Server";
                                        i_arch = "x86_64" });
  assert_equal ~printer:identity "windows_2012R2x64"
               (OVF.get_ostype { i with i_type = "windows";
                                        i_major_version = 6;
                                        i_minor_version = 3;
                                        i_product_variant = "Server";
                                        i_arch = "x86_64" })

(* Suites declaration. *)
let suite =
  "virt-v2v" >:::
    [
      "OVF.get_ostype" >:: test_get_ostype;
    ]

let () =
  run_test_tt_main suite
