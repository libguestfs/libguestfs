(* virt-v2v
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

(* This file tests individual virt-v2v functions. *)

open OUnit2
open Types

open Printf

open Common_utils

let inspect_defaults = {
  i_type = ""; i_distro = ""; i_arch = "";
  i_major_version = 0; i_minor_version = 0;
  i_root = ""; i_package_format = ""; i_package_management = "";
  i_product_name = ""; i_product_variant = ""; i_mountpoints = [];
  i_apps = []; i_apps_map = StringMap.empty; i_firmware = I_BIOS;
  i_windows_systemroot = "";
  i_windows_software_hive = ""; i_windows_system_hive = "";
  i_windows_current_control_set = "";
}

let test_get_ostype ctx =
  let printer = identity in
  assert_equal ~printer "RHEL6"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "linux"; i_distro = "rhel";
                                 i_major_version = 6;
                                 i_minor_version = 0;
                                 i_arch = "i386" });
  assert_equal ~printer "RHEL6x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "linux"; i_distro = "rhel";
                                 i_major_version = 6;
                                 i_minor_version = 0;
                                 i_arch = "x86_64" });
  assert_equal ~printer "rhel_7x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "linux"; i_distro = "rhel";
                                 i_major_version = 7;
                                 i_minor_version = 0;
                                 i_arch = "x86_64" });
  assert_equal ~printer "Windows7"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
                                 i_major_version = 6;
                                 i_minor_version = 1;
                                 i_product_variant = "Client";
                                 i_arch = "i386" });
  assert_equal ~printer "Windows7x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
                                 i_major_version = 6;
                                 i_minor_version = 1;
                                 i_product_variant = "Client";
                                 i_arch = "x86_64" });
  assert_equal ~printer "windows_8"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
                                 i_major_version = 6;
                                 i_minor_version = 2;
                                 i_product_variant = "Client";
                                 i_arch = "i386" });
  assert_equal ~printer "windows_8x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
                                 i_major_version = 6;
                                 i_minor_version = 2;
                                 i_product_variant = "Client";
                                 i_arch = "x86_64" });
  assert_equal ~printer "windows_2012x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
                                 i_major_version = 6;
                                 i_minor_version = 2;
                                 i_product_variant = "Server";
                                 i_arch = "x86_64" });
  assert_equal ~printer "windows_2012R2x64"
               (OVF.get_ostype { inspect_defaults with
                                 i_type = "windows";
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

let test_virtio_iso_path_matches_guest_os ctx =
  (* Windows OSes fake inspection data. *)
  let make_win name major minor variant arch = {
    inspect_defaults with
    i_product_name = name; i_product_variant = variant;
    i_major_version = major; i_minor_version = minor; i_arch = arch;
  } in
  let winxp_32 =     make_win "winxp_32"     5 1 "Client" "i386" in
  let winxp_64 =     make_win "winxp_64"     5 1 "Client" "x86_64" in
  let win2k3_32 =    make_win "win2k3_32"    5 2 "Server" "i386" in
  let win2k3_64 =    make_win "win2k3_64"    5 2 "Server" "x86_64" in
  let winvista_32 =  make_win "winvista_32"  6 0 "Client" "i386" in
  let winvista_64 =  make_win "winvista_64"  6 0 "Client" "x86_64" in
  let win2k8_32 =    make_win "win2k8_32"    6 0 "Server" "i386" in
  let win2k8_64 =    make_win "win2k8_64"    6 0 "Server" "x86_64" in
  let win7_32 =      make_win "win7_32"      6 1 "Client" "i386" in
  let win7_64 =      make_win "win7_64"      6 1 "Client" "x86_64" in
  let win2k8r2_32 =  make_win "win2k8r2_32"  6 1 "Server" "i386" in
  let win2k8r2_64 =  make_win "win2k8r2_64"  6 1 "Server" "x86_64" in
  let win8_32 =      make_win "win8_32"      6 2 "Client" "i386" in
  let win8_64 =      make_win "win8_64"      6 2 "Client" "x86_64" in
  let win2k12_32 =   make_win "win2k12_32"   6 2 "Server" "i386" in
  let win2k12_64 =   make_win "win2k12_64"   6 2 "Server" "x86_64" in
  let win8_1_32 =    make_win "win8_1_32"    6 3 "Client" "i386" in
  let win8_1_64 =    make_win "win8_1_64"    6 3 "Client" "x86_64" in
  let win2k12r2_32 = make_win "win2k12r2_32" 6 3 "Server" "i386" in
  let win2k12r2_64 = make_win "win2k12r2_64" 6 3 "Server" "x86_64" in
  let win10_32 =     make_win "win10_32"     10 0 "Client" "i386" in
  let win10_64 =     make_win "win10_64"     10 0 "Client" "x86_64" in
  let all_windows = [
    winxp_32; win2k3_32; winvista_32; win2k8_32; win7_32; win2k8r2_32;
    win8_32; win2k12_32; win8_1_32; win2k12r2_32; win10_32;
    winxp_64; win2k3_64; winvista_64; win2k8_64; win7_64; win2k8r2_64;
    win8_64; win2k12_64; win8_1_64; win2k12r2_64; win10_64
  ] in

  let paths = [
    (* Paths from the virtio-win 1.7.4 ISO. *)
    "Balloon/2k12/amd64/WdfCoInstaller01011.dll", Some win2k12_64;
    "Balloon/2k12/amd64/balloon.cat", Some win2k12_64;
    "Balloon/2k12/amd64/balloon.inf", Some win2k12_64;
    "Balloon/2k12/amd64/balloon.pdb", Some win2k12_64;
    "Balloon/2k12/amd64/balloon.sys", Some win2k12_64;
    "Balloon/2k12/amd64/blnsvr.exe", Some win2k12_64;
    "Balloon/2k12/amd64/blnsvr.pdb", Some win2k12_64;
    "Balloon/2k12R2/amd64/WdfCoInstaller01011.dll", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/balloon.cat", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/balloon.inf", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/balloon.pdb", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/balloon.sys", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/blnsvr.exe", Some win2k12r2_64;
    "Balloon/2k12R2/amd64/blnsvr.pdb", Some win2k12r2_64;
    "Balloon/2k3/amd64/WdfCoInstaller01009.dll", Some win2k3_64;
    "Balloon/2k3/amd64/balloon.cat", Some win2k3_64;
    "Balloon/2k3/amd64/balloon.inf", Some win2k3_64;
    "Balloon/2k3/amd64/balloon.pdb", Some win2k3_64;
    "Balloon/2k3/amd64/balloon.sys", Some win2k3_64;
    "Balloon/2k3/amd64/blnsvr.exe", Some win2k3_64;
    "Balloon/2k3/amd64/blnsvr.pdb", Some win2k3_64;
    "Balloon/2k3/x86/WdfCoInstaller01009.dll", Some win2k3_32;
    "Balloon/2k3/x86/balloon.cat", Some win2k3_32;
    "Balloon/2k3/x86/balloon.inf", Some win2k3_32;
    "Balloon/2k3/x86/balloon.pdb", Some win2k3_32;
    "Balloon/2k3/x86/balloon.sys", Some win2k3_32;
    "Balloon/2k3/x86/blnsvr.exe", Some win2k3_32;
    "Balloon/2k3/x86/blnsvr.pdb", Some win2k3_32;
    "Balloon/2k8/amd64/WdfCoInstaller01009.dll", Some win2k8_64;
    "Balloon/2k8/amd64/balloon.cat", Some win2k8_64;
    "Balloon/2k8/amd64/balloon.inf", Some win2k8_64;
    "Balloon/2k8/amd64/balloon.pdb", Some win2k8_64;
    "Balloon/2k8/amd64/balloon.sys", Some win2k8_64;
    "Balloon/2k8/amd64/blnsvr.exe", Some win2k8_64;
    "Balloon/2k8/amd64/blnsvr.pdb", Some win2k8_64;
    "Balloon/2k8/x86/WdfCoInstaller01009.dll", Some win2k8_32;
    "Balloon/2k8/x86/balloon.cat", Some win2k8_32;
    "Balloon/2k8/x86/balloon.inf", Some win2k8_32;
    "Balloon/2k8/x86/balloon.pdb", Some win2k8_32;
    "Balloon/2k8/x86/balloon.sys", Some win2k8_32;
    "Balloon/2k8/x86/blnsvr.exe", Some win2k8_32;
    "Balloon/2k8/x86/blnsvr.pdb", Some win2k8_32;
    "Balloon/2k8R2/amd64/WdfCoInstaller01009.dll", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/balloon.cat", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/balloon.inf", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/balloon.pdb", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/balloon.sys", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/blnsvr.exe", Some win2k8r2_64;
    "Balloon/2k8R2/amd64/blnsvr.pdb", Some win2k8r2_64;
    "Balloon/w7/amd64/WdfCoInstaller01009.dll", Some win7_64;
    "Balloon/w7/amd64/balloon.cat", Some win7_64;
    "Balloon/w7/amd64/balloon.inf", Some win7_64;
    "Balloon/w7/amd64/balloon.pdb", Some win7_64;
    "Balloon/w7/amd64/balloon.sys", Some win7_64;
    "Balloon/w7/amd64/blnsvr.exe", Some win7_64;
    "Balloon/w7/amd64/blnsvr.pdb", Some win7_64;
    "Balloon/w7/x86/WdfCoInstaller01009.dll", Some win7_32;
    "Balloon/w7/x86/balloon.cat", Some win7_32;
    "Balloon/w7/x86/balloon.inf", Some win7_32;
    "Balloon/w7/x86/balloon.pdb", Some win7_32;
    "Balloon/w7/x86/balloon.sys", Some win7_32;
    "Balloon/w7/x86/blnsvr.exe", Some win7_32;
    "Balloon/w7/x86/blnsvr.pdb", Some win7_32;
    "Balloon/w8.1/amd64/WdfCoInstaller01011.dll", Some win8_1_64;
    "Balloon/w8.1/amd64/balloon.cat", Some win8_1_64;
    "Balloon/w8.1/amd64/balloon.inf", Some win8_1_64;
    "Balloon/w8.1/amd64/balloon.pdb", Some win8_1_64;
    "Balloon/w8.1/amd64/balloon.sys", Some win8_1_64;
    "Balloon/w8.1/amd64/blnsvr.exe", Some win8_1_64;
    "Balloon/w8.1/amd64/blnsvr.pdb", Some win8_1_64;
    "Balloon/w8.1/x86/WdfCoInstaller01011.dll", Some win8_1_32;
    "Balloon/w8.1/x86/balloon.cat", Some win8_1_32;
    "Balloon/w8.1/x86/balloon.inf", Some win8_1_32;
    "Balloon/w8.1/x86/balloon.pdb", Some win8_1_32;
    "Balloon/w8.1/x86/balloon.sys", Some win8_1_32;
    "Balloon/w8.1/x86/blnsvr.exe", Some win8_1_32;
    "Balloon/w8.1/x86/blnsvr.pdb", Some win8_1_32;
    "Balloon/w8/amd64/WdfCoInstaller01011.dll", Some win8_64;
    "Balloon/w8/amd64/balloon.cat", Some win8_64;
    "Balloon/w8/amd64/balloon.inf", Some win8_64;
    "Balloon/w8/amd64/balloon.pdb", Some win8_64;
    "Balloon/w8/amd64/balloon.sys", Some win8_64;
    "Balloon/w8/amd64/blnsvr.exe", Some win8_64;
    "Balloon/w8/amd64/blnsvr.pdb", Some win8_64;
    "Balloon/w8/x86/WdfCoInstaller01011.dll", Some win8_32;
    "Balloon/w8/x86/balloon.cat", Some win8_32;
    "Balloon/w8/x86/balloon.inf", Some win8_32;
    "Balloon/w8/x86/balloon.pdb", Some win8_32;
    "Balloon/w8/x86/balloon.sys", Some win8_32;
    "Balloon/w8/x86/blnsvr.exe", Some win8_32;
    "Balloon/w8/x86/blnsvr.pdb", Some win8_32;
    "Balloon/xp/x86/WdfCoInstaller01009.dll", Some winxp_32;
    "Balloon/xp/x86/balloon.cat", Some winxp_32;
    "Balloon/xp/x86/balloon.inf", Some winxp_32;
    "Balloon/xp/x86/balloon.pdb", Some winxp_32;
    "Balloon/xp/x86/balloon.sys", Some winxp_32;
    "Balloon/xp/x86/blnsvr.exe", Some winxp_32;
    "Balloon/xp/x86/blnsvr.pdb", Some winxp_32;
    "NetKVM/2k12/amd64/netkvm.cat", Some win2k12_64;
    "NetKVM/2k12/amd64/netkvm.inf", Some win2k12_64;
    "NetKVM/2k12/amd64/netkvm.pdb", Some win2k12_64;
    "NetKVM/2k12/amd64/netkvm.sys", Some win2k12_64;
    "NetKVM/2k12/amd64/netkvmco.dll", Some win2k12_64;
    "NetKVM/2k12/amd64/readme.doc", Some win2k12_64;
    "NetKVM/2k12R2/amd64/netkvm.cat", Some win2k12r2_64;
    "NetKVM/2k12R2/amd64/netkvm.inf", Some win2k12r2_64;
    "NetKVM/2k12R2/amd64/netkvm.pdb", Some win2k12r2_64;
    "NetKVM/2k12R2/amd64/netkvm.sys", Some win2k12r2_64;
    "NetKVM/2k12R2/amd64/netkvmco.dll", Some win2k12r2_64;
    "NetKVM/2k12R2/amd64/readme.doc", Some win2k12r2_64;
    "NetKVM/2k3/amd64/netkvm.cat", Some win2k3_64;
    "NetKVM/2k3/amd64/netkvm.inf", Some win2k3_64;
    "NetKVM/2k3/amd64/netkvm.pdb", Some win2k3_64;
    "NetKVM/2k3/amd64/netkvm.sys", Some win2k3_64;
    "NetKVM/2k3/x86/netkvm.cat", Some win2k3_32;
    "NetKVM/2k3/x86/netkvm.inf", Some win2k3_32;
    "NetKVM/2k3/x86/netkvm.pdb", Some win2k3_32;
    "NetKVM/2k3/x86/netkvm.sys", Some win2k3_32;
    "NetKVM/2k8/amd64/netkvm.cat", Some win2k8_64;
    "NetKVM/2k8/amd64/netkvm.inf", Some win2k8_64;
    "NetKVM/2k8/amd64/netkvm.pdb", Some win2k8_64;
    "NetKVM/2k8/amd64/netkvm.sys", Some win2k8_64;
    "NetKVM/2k8/amd64/netkvmco.dll", Some win2k8_64;
    "NetKVM/2k8/amd64/readme.doc", Some win2k8_64;
    "NetKVM/2k8/x86/netkvm.cat", Some win2k8_32;
    "NetKVM/2k8/x86/netkvm.inf", Some win2k8_32;
    "NetKVM/2k8/x86/netkvm.pdb", Some win2k8_32;
    "NetKVM/2k8/x86/netkvm.sys", Some win2k8_32;
    "NetKVM/2k8/x86/netkvmco.dll", Some win2k8_32;
    "NetKVM/2k8/x86/readme.doc", Some win2k8_32;
    "NetKVM/2k8R2/amd64/netkvm.cat", Some win2k8r2_64;
    "NetKVM/2k8R2/amd64/netkvm.inf", Some win2k8r2_64;
    "NetKVM/2k8R2/amd64/netkvm.pdb", Some win2k8r2_64;
    "NetKVM/2k8R2/amd64/netkvm.sys", Some win2k8r2_64;
    "NetKVM/2k8R2/amd64/netkvmco.dll", Some win2k8r2_64;
    "NetKVM/2k8R2/amd64/readme.doc", Some win2k8r2_64;
    "NetKVM/w7/amd64/netkvm.cat", Some win7_64;
    "NetKVM/w7/amd64/netkvm.inf", Some win7_64;
    "NetKVM/w7/amd64/netkvm.pdb", Some win7_64;
    "NetKVM/w7/amd64/netkvm.sys", Some win7_64;
    "NetKVM/w7/amd64/netkvmco.dll", Some win7_64;
    "NetKVM/w7/amd64/readme.doc", Some win7_64;
    "NetKVM/w7/x86/netkvm.cat", Some win7_32;
    "NetKVM/w7/x86/netkvm.inf", Some win7_32;
    "NetKVM/w7/x86/netkvm.pdb", Some win7_32;
    "NetKVM/w7/x86/netkvm.sys", Some win7_32;
    "NetKVM/w7/x86/netkvmco.dll", Some win7_32;
    "NetKVM/w7/x86/readme.doc", Some win7_32;
    "NetKVM/w8.1/amd64/netkvm.cat", Some win8_1_64;
    "NetKVM/w8.1/amd64/netkvm.inf", Some win8_1_64;
    "NetKVM/w8.1/amd64/netkvm.pdb", Some win8_1_64;
    "NetKVM/w8.1/amd64/netkvm.sys", Some win8_1_64;
    "NetKVM/w8.1/amd64/netkvmco.dll", Some win8_1_64;
    "NetKVM/w8.1/amd64/readme.doc", Some win8_1_64;
    "NetKVM/w8.1/x86/netkvm.cat", Some win8_1_32;
    "NetKVM/w8.1/x86/netkvm.inf", Some win8_1_32;
    "NetKVM/w8.1/x86/netkvm.pdb", Some win8_1_32;
    "NetKVM/w8.1/x86/netkvm.sys", Some win8_1_32;
    "NetKVM/w8.1/x86/netkvmco.dll", Some win8_1_32;
    "NetKVM/w8.1/x86/readme.doc", Some win8_1_32;
    "NetKVM/w8/amd64/netkvm.cat", Some win8_64;
    "NetKVM/w8/amd64/netkvm.inf", Some win8_64;
    "NetKVM/w8/amd64/netkvm.pdb", Some win8_64;
    "NetKVM/w8/amd64/netkvm.sys", Some win8_64;
    "NetKVM/w8/amd64/netkvmco.dll", Some win8_64;
    "NetKVM/w8/amd64/readme.doc", Some win8_64;
    "NetKVM/w8/x86/netkvm.cat", Some win8_32;
    "NetKVM/w8/x86/netkvm.inf", Some win8_32;
    "NetKVM/w8/x86/netkvm.pdb", Some win8_32;
    "NetKVM/w8/x86/netkvm.sys", Some win8_32;
    "NetKVM/w8/x86/netkvmco.dll", Some win8_32;
    "NetKVM/w8/x86/readme.doc", Some win8_32;
    "NetKVM/xp/x86/netkvm.cat", Some winxp_32;
    "NetKVM/xp/x86/netkvm.inf", Some winxp_32;
    "NetKVM/xp/x86/netkvm.pdb", Some winxp_32;
    "NetKVM/xp/x86/netkvm.sys", Some winxp_32;
    "guest-agent/qemu-ga-x64.msi", None;
    "guest-agent/qemu-ga-x86.msi", None;
    "qemupciserial/qemupciserial.inf", None;
    "viorng/2k12/amd64/WdfCoInstaller01011.dll", Some win2k12_64;
    "viorng/2k12/amd64/viorng.cat", Some win2k12_64;
    "viorng/2k12/amd64/viorng.inf", Some win2k12_64;
    "viorng/2k12/amd64/viorng.pdb", Some win2k12_64;
    "viorng/2k12/amd64/viorng.sys", Some win2k12_64;
    "viorng/2k12/amd64/viorngci.dll", Some win2k12_64;
    "viorng/2k12/amd64/viorngum.dll", Some win2k12_64;
    "viorng/2k12R2/amd64/WdfCoInstaller01011.dll", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorng.cat", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorng.inf", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorng.pdb", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorng.sys", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorngci.dll", Some win2k12r2_64;
    "viorng/2k12R2/amd64/viorngum.dll", Some win2k12r2_64;
    "viorng/2k8/amd64/WdfCoInstaller01009.dll", Some win2k8_64;
    "viorng/2k8/amd64/viorng.cat", Some win2k8_64;
    "viorng/2k8/amd64/viorng.inf", Some win2k8_64;
    "viorng/2k8/amd64/viorng.pdb", Some win2k8_64;
    "viorng/2k8/amd64/viorng.sys", Some win2k8_64;
    "viorng/2k8/amd64/viorngci.dll", Some win2k8_64;
    "viorng/2k8/amd64/viorngum.dll", Some win2k8_64;
    "viorng/2k8/x86/WdfCoInstaller01009.dll", Some win2k8_32;
    "viorng/2k8/x86/viorng.cat", Some win2k8_32;
    "viorng/2k8/x86/viorng.inf", Some win2k8_32;
    "viorng/2k8/x86/viorng.pdb", Some win2k8_32;
    "viorng/2k8/x86/viorng.sys", Some win2k8_32;
    "viorng/2k8/x86/viorngci.dll", Some win2k8_32;
    "viorng/2k8/x86/viorngum.dll", Some win2k8_32;
    "viorng/2k8R2/amd64/WdfCoInstaller01009.dll", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorng.cat", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorng.inf", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorng.pdb", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorng.sys", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorngci.dll", Some win2k8r2_64;
    "viorng/2k8R2/amd64/viorngum.dll", Some win2k8r2_64;
    "viorng/w7/amd64/WdfCoInstaller01009.dll", Some win7_64;
    "viorng/w7/amd64/viorng.cat", Some win7_64;
    "viorng/w7/amd64/viorng.inf", Some win7_64;
    "viorng/w7/amd64/viorng.pdb", Some win7_64;
    "viorng/w7/amd64/viorng.sys", Some win7_64;
    "viorng/w7/amd64/viorngci.dll", Some win7_64;
    "viorng/w7/amd64/viorngum.dll", Some win7_64;
    "viorng/w7/x86/WdfCoInstaller01009.dll", Some win7_32;
    "viorng/w7/x86/viorng.cat", Some win7_32;
    "viorng/w7/x86/viorng.inf", Some win7_32;
    "viorng/w7/x86/viorng.pdb", Some win7_32;
    "viorng/w7/x86/viorng.sys", Some win7_32;
    "viorng/w7/x86/viorngci.dll", Some win7_32;
    "viorng/w7/x86/viorngum.dll", Some win7_32;
    "viorng/w8.1/amd64/WdfCoInstaller01011.dll", Some win8_1_64;
    "viorng/w8.1/amd64/viorng.cat", Some win8_1_64;
    "viorng/w8.1/amd64/viorng.inf", Some win8_1_64;
    "viorng/w8.1/amd64/viorng.pdb", Some win8_1_64;
    "viorng/w8.1/amd64/viorng.sys", Some win8_1_64;
    "viorng/w8.1/amd64/viorngci.dll", Some win8_1_64;
    "viorng/w8.1/amd64/viorngum.dll", Some win8_1_64;
    "viorng/w8.1/x86/WdfCoInstaller01011.dll", Some win8_1_32;
    "viorng/w8.1/x86/viorng.cat", Some win8_1_32;
    "viorng/w8.1/x86/viorng.inf", Some win8_1_32;
    "viorng/w8.1/x86/viorng.pdb", Some win8_1_32;
    "viorng/w8.1/x86/viorng.sys", Some win8_1_32;
    "viorng/w8.1/x86/viorngci.dll", Some win8_1_32;
    "viorng/w8.1/x86/viorngum.dll", Some win8_1_32;
    "viorng/w8/amd64/WdfCoInstaller01011.dll", Some win8_64;
    "viorng/w8/amd64/viorng.cat", Some win8_64;
    "viorng/w8/amd64/viorng.inf", Some win8_64;
    "viorng/w8/amd64/viorng.pdb", Some win8_64;
    "viorng/w8/amd64/viorng.sys", Some win8_64;
    "viorng/w8/amd64/viorngci.dll", Some win8_64;
    "viorng/w8/amd64/viorngum.dll", Some win8_64;
    "viorng/w8/x86/WdfCoInstaller01011.dll", Some win8_32;
    "viorng/w8/x86/viorng.cat", Some win8_32;
    "viorng/w8/x86/viorng.inf", Some win8_32;
    "viorng/w8/x86/viorng.pdb", Some win8_32;
    "viorng/w8/x86/viorng.sys", Some win8_32;
    "viorng/w8/x86/viorngci.dll", Some win8_32;
    "viorng/w8/x86/viorngum.dll", Some win8_32;
    "vioscsi/2k12/amd64/vioscsi.cat", Some win2k12_64;
    "vioscsi/2k12/amd64/vioscsi.inf", Some win2k12_64;
    "vioscsi/2k12/amd64/vioscsi.pdb", Some win2k12_64;
    "vioscsi/2k12/amd64/vioscsi.sys", Some win2k12_64;
    "vioscsi/2k12R2/amd64/vioscsi.cat", Some win2k12r2_64;
    "vioscsi/2k12R2/amd64/vioscsi.inf", Some win2k12r2_64;
    "vioscsi/2k12R2/amd64/vioscsi.pdb", Some win2k12r2_64;
    "vioscsi/2k12R2/amd64/vioscsi.sys", Some win2k12r2_64;
    "vioscsi/2k8/amd64/vioscsi.cat", Some win2k8_64;
    "vioscsi/2k8/amd64/vioscsi.inf", Some win2k8_64;
    "vioscsi/2k8/amd64/vioscsi.pdb", Some win2k8_64;
    "vioscsi/2k8/amd64/vioscsi.sys", Some win2k8_64;
    "vioscsi/2k8/x86/vioscsi.cat", Some win2k8_32;
    "vioscsi/2k8/x86/vioscsi.inf", Some win2k8_32;
    "vioscsi/2k8/x86/vioscsi.pdb", Some win2k8_32;
    "vioscsi/2k8/x86/vioscsi.sys", Some win2k8_32;
    "vioscsi/2k8R2/amd64/vioscsi.cat", Some win2k8r2_64;
    "vioscsi/2k8R2/amd64/vioscsi.inf", Some win2k8r2_64;
    "vioscsi/2k8R2/amd64/vioscsi.pdb", Some win2k8r2_64;
    "vioscsi/2k8R2/amd64/vioscsi.sys", Some win2k8r2_64;
    "vioscsi/w7/amd64/vioscsi.cat", Some win7_64;
    "vioscsi/w7/amd64/vioscsi.inf", Some win7_64;
    "vioscsi/w7/amd64/vioscsi.pdb", Some win7_64;
    "vioscsi/w7/amd64/vioscsi.sys", Some win7_64;
    "vioscsi/w7/x86/vioscsi.cat", Some win7_32;
    "vioscsi/w7/x86/vioscsi.inf", Some win7_32;
    "vioscsi/w7/x86/vioscsi.pdb", Some win7_32;
    "vioscsi/w7/x86/vioscsi.sys", Some win7_32;
    "vioscsi/w8.1/amd64/vioscsi.cat", Some win8_1_64;
    "vioscsi/w8.1/amd64/vioscsi.inf", Some win8_1_64;
    "vioscsi/w8.1/amd64/vioscsi.pdb", Some win8_1_64;
    "vioscsi/w8.1/amd64/vioscsi.sys", Some win8_1_64;
    "vioscsi/w8.1/x86/vioscsi.cat", Some win8_1_32;
    "vioscsi/w8.1/x86/vioscsi.inf", Some win8_1_32;
    "vioscsi/w8.1/x86/vioscsi.pdb", Some win8_1_32;
    "vioscsi/w8.1/x86/vioscsi.sys", Some win8_1_32;
    "vioscsi/w8/amd64/vioscsi.cat", Some win8_64;
    "vioscsi/w8/amd64/vioscsi.inf", Some win8_64;
    "vioscsi/w8/amd64/vioscsi.pdb", Some win8_64;
    "vioscsi/w8/amd64/vioscsi.sys", Some win8_64;
    "vioscsi/w8/x86/vioscsi.cat", Some win8_32;
    "vioscsi/w8/x86/vioscsi.inf", Some win8_32;
    "vioscsi/w8/x86/vioscsi.pdb", Some win8_32;
    "vioscsi/w8/x86/vioscsi.sys", Some win8_32;
    "vioserial/2k12/amd64/WdfCoInstaller01011.dll", Some win2k12_64;
    "vioserial/2k12/amd64/vioser.cat", Some win2k12_64;
    "vioserial/2k12/amd64/vioser.inf", Some win2k12_64;
    "vioserial/2k12/amd64/vioser.pdb", Some win2k12_64;
    "vioserial/2k12/amd64/vioser.sys", Some win2k12_64;
    "vioserial/2k12R2/amd64/WdfCoInstaller01011.dll", Some win2k12r2_64;
    "vioserial/2k12R2/amd64/vioser.cat", Some win2k12r2_64;
    "vioserial/2k12R2/amd64/vioser.inf", Some win2k12r2_64;
    "vioserial/2k12R2/amd64/vioser.pdb", Some win2k12r2_64;
    "vioserial/2k12R2/amd64/vioser.sys", Some win2k12r2_64;
    "vioserial/2k3/amd64/WdfCoInstaller01009.dll", Some win2k3_64;
    "vioserial/2k3/amd64/vioser.cat", Some win2k3_64;
    "vioserial/2k3/amd64/vioser.inf", Some win2k3_64;
    "vioserial/2k3/amd64/vioser.pdb", Some win2k3_64;
    "vioserial/2k3/amd64/vioser.sys", Some win2k3_64;
    "vioserial/2k3/x86/WdfCoInstaller01009.dll", Some win2k3_32;
    "vioserial/2k3/x86/vioser.cat", Some win2k3_32;
    "vioserial/2k3/x86/vioser.inf", Some win2k3_32;
    "vioserial/2k3/x86/vioser.pdb", Some win2k3_32;
    "vioserial/2k3/x86/vioser.sys", Some win2k3_32;
    "vioserial/2k8/amd64/WdfCoInstaller01009.dll", Some win2k8_64;
    "vioserial/2k8/amd64/vioser.cat", Some win2k8_64;
    "vioserial/2k8/amd64/vioser.inf", Some win2k8_64;
    "vioserial/2k8/amd64/vioser.pdb", Some win2k8_64;
    "vioserial/2k8/amd64/vioser.sys", Some win2k8_64;
    "vioserial/2k8/x86/WdfCoInstaller01009.dll", Some win2k8_32;
    "vioserial/2k8/x86/vioser.cat", Some win2k8_32;
    "vioserial/2k8/x86/vioser.inf", Some win2k8_32;
    "vioserial/2k8/x86/vioser.pdb", Some win2k8_32;
    "vioserial/2k8/x86/vioser.sys", Some win2k8_32;
    "vioserial/2k8R2/amd64/WdfCoInstaller01009.dll", Some win2k8r2_64;
    "vioserial/2k8R2/amd64/vioser.cat", Some win2k8r2_64;
    "vioserial/2k8R2/amd64/vioser.inf", Some win2k8r2_64;
    "vioserial/2k8R2/amd64/vioser.pdb", Some win2k8r2_64;
    "vioserial/2k8R2/amd64/vioser.sys", Some win2k8r2_64;
    "vioserial/w7/amd64/WdfCoInstaller01009.dll", Some win7_64;
    "vioserial/w7/amd64/vioser.cat", Some win7_64;
    "vioserial/w7/amd64/vioser.inf", Some win7_64;
    "vioserial/w7/amd64/vioser.pdb", Some win7_64;
    "vioserial/w7/amd64/vioser.sys", Some win7_64;
    "vioserial/w7/x86/WdfCoInstaller01009.dll", Some win7_32;
    "vioserial/w7/x86/vioser.cat", Some win7_32;
    "vioserial/w7/x86/vioser.inf", Some win7_32;
    "vioserial/w7/x86/vioser.pdb", Some win7_32;
    "vioserial/w7/x86/vioser.sys", Some win7_32;
    "vioserial/w8.1/amd64/WdfCoInstaller01011.dll", Some win8_1_64;
    "vioserial/w8.1/amd64/vioser.cat", Some win8_1_64;
    "vioserial/w8.1/amd64/vioser.inf", Some win8_1_64;
    "vioserial/w8.1/amd64/vioser.pdb", Some win8_1_64;
    "vioserial/w8.1/amd64/vioser.sys", Some win8_1_64;
    "vioserial/w8.1/x86/WdfCoInstaller01011.dll", Some win8_1_32;
    "vioserial/w8.1/x86/vioser.cat", Some win8_1_32;
    "vioserial/w8.1/x86/vioser.inf", Some win8_1_32;
    "vioserial/w8.1/x86/vioser.pdb", Some win8_1_32;
    "vioserial/w8.1/x86/vioser.sys", Some win8_1_32;
    "vioserial/w8/amd64/WdfCoInstaller01011.dll", Some win8_64;
    "vioserial/w8/amd64/vioser.cat", Some win8_64;
    "vioserial/w8/amd64/vioser.inf", Some win8_64;
    "vioserial/w8/amd64/vioser.pdb", Some win8_64;
    "vioserial/w8/amd64/vioser.sys", Some win8_64;
    "vioserial/w8/x86/WdfCoInstaller01011.dll", Some win8_32;
    "vioserial/w8/x86/vioser.cat", Some win8_32;
    "vioserial/w8/x86/vioser.inf", Some win8_32;
    "vioserial/w8/x86/vioser.pdb", Some win8_32;
    "vioserial/w8/x86/vioser.sys", Some win8_32;
    "vioserial/xp/x86/WdfCoInstaller01009.dll", Some winxp_32;
    "vioserial/xp/x86/vioser.cat", Some winxp_32;
    "vioserial/xp/x86/vioser.inf", Some winxp_32;
    "vioserial/xp/x86/vioser.pdb", Some winxp_32;
    "vioserial/xp/x86/vioser.sys", Some winxp_32;
    "viostor/2k12/amd64/viostor.cat", Some win2k12_64;
    "viostor/2k12/amd64/viostor.inf", Some win2k12_64;
    "viostor/2k12/amd64/viostor.pdb", Some win2k12_64;
    "viostor/2k12/amd64/viostor.sys", Some win2k12_64;
    "viostor/2k12R2/amd64/viostor.cat", Some win2k12r2_64;
    "viostor/2k12R2/amd64/viostor.inf", Some win2k12r2_64;
    "viostor/2k12R2/amd64/viostor.pdb", Some win2k12r2_64;
    "viostor/2k12R2/amd64/viostor.sys", Some win2k12r2_64;
    "viostor/2k3/amd64/viostor.cat", Some win2k3_64;
    "viostor/2k3/amd64/viostor.inf", Some win2k3_64;
    "viostor/2k3/amd64/viostor.pdb", Some win2k3_64;
    "viostor/2k3/amd64/viostor.sys", Some win2k3_64;
    "viostor/2k3/x86/viostor.cat", Some win2k3_32;
    "viostor/2k3/x86/viostor.inf", Some win2k3_32;
    "viostor/2k3/x86/viostor.pdb", Some win2k3_32;
    "viostor/2k3/x86/viostor.sys", Some win2k3_32;
    "viostor/2k8/amd64/viostor.cat", Some win2k8_64;
    "viostor/2k8/amd64/viostor.inf", Some win2k8_64;
    "viostor/2k8/amd64/viostor.pdb", Some win2k8_64;
    "viostor/2k8/amd64/viostor.sys", Some win2k8_64;
    "viostor/2k8/x86/viostor.cat", Some win2k8_32;
    "viostor/2k8/x86/viostor.inf", Some win2k8_32;
    "viostor/2k8/x86/viostor.pdb", Some win2k8_32;
    "viostor/2k8/x86/viostor.sys", Some win2k8_32;
    "viostor/2k8R2/amd64/viostor.cat", Some win2k8r2_64;
    "viostor/2k8R2/amd64/viostor.inf", Some win2k8r2_64;
    "viostor/2k8R2/amd64/viostor.pdb", Some win2k8r2_64;
    "viostor/2k8R2/amd64/viostor.sys", Some win2k8r2_64;
    "viostor/w7/amd64/viostor.cat", Some win7_64;
    "viostor/w7/amd64/viostor.inf", Some win7_64;
    "viostor/w7/amd64/viostor.pdb", Some win7_64;
    "viostor/w7/amd64/viostor.sys", Some win7_64;
    "viostor/w7/x86/viostor.cat", Some win7_32;
    "viostor/w7/x86/viostor.inf", Some win7_32;
    "viostor/w7/x86/viostor.pdb", Some win7_32;
    "viostor/w7/x86/viostor.sys", Some win7_32;
    "viostor/w8.1/amd64/viostor.cat", Some win8_1_64;
    "viostor/w8.1/amd64/viostor.inf", Some win8_1_64;
    "viostor/w8.1/amd64/viostor.pdb", Some win8_1_64;
    "viostor/w8.1/amd64/viostor.sys", Some win8_1_64;
    "viostor/w8.1/x86/viostor.cat", Some win8_1_32;
    "viostor/w8.1/x86/viostor.inf", Some win8_1_32;
    "viostor/w8.1/x86/viostor.pdb", Some win8_1_32;
    "viostor/w8.1/x86/viostor.sys", Some win8_1_32;
    "viostor/w8/amd64/viostor.cat", Some win8_64;
    "viostor/w8/amd64/viostor.inf", Some win8_64;
    "viostor/w8/amd64/viostor.pdb", Some win8_64;
    "viostor/w8/amd64/viostor.sys", Some win8_64;
    "viostor/w8/x86/viostor.cat", Some win8_32;
    "viostor/w8/x86/viostor.inf", Some win8_32;
    "viostor/w8/x86/viostor.pdb", Some win8_32;
    "viostor/w8/x86/viostor.sys", Some win8_32;
    "viostor/xp/x86/viostor.cat", Some winxp_32;
    "viostor/xp/x86/viostor.inf", Some winxp_32;
    "viostor/xp/x86/viostor.pdb", Some winxp_32;
    "viostor/xp/x86/viostor.sys", Some winxp_32;
    "virtio-win-1.7.4_amd64.vfd", None;
    "virtio-win-1.7.4_x86.vfd", None;
    "virtio-win_license.txt", None;

    (* Paths from the unpacked virtio-win 1.7.4 directory. *)
    "virtio-win-1.7.4.iso", None;
    "virtio-win-1.7.4_amd64.vfd", None;
    "guest-agent/qemu-ga-x86.msi", None;
    "guest-agent/qemu-ga-x64.msi", None;
    "drivers/i386/Win8.1/viostor.inf", Some win8_1_32;
    "drivers/i386/Win8.1/viostor.sys", Some win8_1_32;
    "drivers/i386/Win8.1/vioscsi.cat", Some win8_1_32;
    "drivers/i386/Win8.1/netkvm.inf", Some win8_1_32;
    "drivers/i386/Win8.1/netkvm.sys", Some win8_1_32;
    "drivers/i386/Win8.1/viostor.cat", Some win8_1_32;
    "drivers/i386/Win8.1/vioscsi.sys", Some win8_1_32;
    "drivers/i386/Win8.1/netkvm.cat", Some win8_1_32;
    "drivers/i386/Win8.1/vioscsi.inf", Some win8_1_32;
    "drivers/i386/Win2008/viostor.inf", Some win2k8_32;
    "drivers/i386/Win2008/viostor.sys", Some win2k8_32;
    "drivers/i386/Win2008/vioscsi.cat", Some win2k8_32;
    "drivers/i386/Win2008/netkvm.inf", Some win2k8_32;
    "drivers/i386/Win2008/netkvm.sys", Some win2k8_32;
    "drivers/i386/Win2008/viostor.cat", Some win2k8_32;
    "drivers/i386/Win2008/vioscsi.sys", Some win2k8_32;
    "drivers/i386/Win2008/netkvm.cat", Some win2k8_32;
    "drivers/i386/Win2008/vioscsi.inf", Some win2k8_32;
    "drivers/i386/Win7/viostor.inf", Some win7_32;
    "drivers/i386/Win7/viostor.sys", Some win7_32;
    "drivers/i386/Win7/qxldd.dll", Some win7_32;
    "drivers/i386/Win7/qxl.sys", Some win7_32;
    "drivers/i386/Win7/vioscsi.cat", Some win7_32;
    "drivers/i386/Win7/netkvm.inf", Some win7_32;
    "drivers/i386/Win7/netkvm.sys", Some win7_32;
    "drivers/i386/Win7/viostor.cat", Some win7_32;
    "drivers/i386/Win7/qxl.inf", Some win7_32;
    "drivers/i386/Win7/vioscsi.sys", Some win7_32;
    "drivers/i386/Win7/qxl.cat", Some win7_32;
    "drivers/i386/Win7/netkvm.cat", Some win7_32;
    "drivers/i386/Win7/vioscsi.inf", Some win7_32;
    "drivers/i386/Win2003/viostor.inf", Some win2k3_32;
    "drivers/i386/Win2003/viostor.sys", Some win2k3_32;
    "drivers/i386/Win2003/netkvm.inf", Some win2k3_32;
    "drivers/i386/Win2003/netkvm.sys", Some win2k3_32;
    "drivers/i386/Win2003/viostor.cat", Some win2k3_32;
    "drivers/i386/Win2003/netkvm.cat", Some win2k3_32;
    "drivers/i386/Win8/viostor.inf", Some win8_32;
    "drivers/i386/Win8/viostor.sys", Some win8_32;
    "drivers/i386/Win8/vioscsi.cat", Some win8_32;
    "drivers/i386/Win8/netkvm.inf", Some win8_32;
    "drivers/i386/Win8/netkvm.sys", Some win8_32;
    "drivers/i386/Win8/viostor.cat", Some win8_32;
    "drivers/i386/Win8/vioscsi.sys", Some win8_32;
    "drivers/i386/Win8/netkvm.cat", Some win8_32;
    "drivers/i386/Win8/vioscsi.inf", Some win8_32;
    "drivers/i386/WinXP/viostor.inf", Some winxp_32;
    "drivers/i386/WinXP/viostor.sys", Some winxp_32;
    "drivers/i386/WinXP/qxldd.dll", Some winxp_32;
    "drivers/i386/WinXP/qxl.sys", Some winxp_32;
    "drivers/i386/WinXP/netkvm.inf", Some winxp_32;
    "drivers/i386/WinXP/netkvm.sys", Some winxp_32;
    "drivers/i386/WinXP/viostor.cat", Some winxp_32;
    "drivers/i386/WinXP/qxl.inf", Some winxp_32;
    "drivers/i386/WinXP/qxl.cat", Some winxp_32;
    "drivers/i386/WinXP/netkvm.cat", Some winxp_32;
    "drivers/amd64/Win8.1/viostor.inf", Some win8_1_64;
    "drivers/amd64/Win8.1/viostor.sys", Some win8_1_64;
    "drivers/amd64/Win8.1/vioscsi.cat", Some win8_1_64;
    "drivers/amd64/Win8.1/netkvm.inf", Some win8_1_64;
    "drivers/amd64/Win8.1/netkvm.sys", Some win8_1_64;
    "drivers/amd64/Win8.1/viostor.cat", Some win8_1_64;
    "drivers/amd64/Win8.1/vioscsi.sys", Some win8_1_64;
    "drivers/amd64/Win8.1/netkvm.cat", Some win8_1_64;
    "drivers/amd64/Win8.1/vioscsi.inf", Some win8_1_64;
    "drivers/amd64/Win2008/viostor.inf", Some win2k8_64;
    "drivers/amd64/Win2008/viostor.sys", Some win2k8_64;
    "drivers/amd64/Win2008/vioscsi.cat", Some win2k8_64;
    "drivers/amd64/Win2008/netkvm.inf", Some win2k8_64;
    "drivers/amd64/Win2008/netkvm.sys", Some win2k8_64;
    "drivers/amd64/Win2008/viostor.cat", Some win2k8_64;
    "drivers/amd64/Win2008/vioscsi.sys", Some win2k8_64;
    "drivers/amd64/Win2008/netkvm.cat", Some win2k8_64;
    "drivers/amd64/Win2008/vioscsi.inf", Some win2k8_64;
    "drivers/amd64/Win7/viostor.inf", Some win7_64;
    "drivers/amd64/Win7/viostor.sys", Some win7_64;
    "drivers/amd64/Win7/qxldd.dll", Some win7_64;
    "drivers/amd64/Win7/qxl.sys", Some win7_64;
    "drivers/amd64/Win7/vioscsi.cat", Some win7_64;
    "drivers/amd64/Win7/netkvm.inf", Some win7_64;
    "drivers/amd64/Win7/netkvm.sys", Some win7_64;
    "drivers/amd64/Win7/viostor.cat", Some win7_64;
    "drivers/amd64/Win7/qxl.inf", Some win7_64;
    "drivers/amd64/Win7/vioscsi.sys", Some win7_64;
    "drivers/amd64/Win7/qxl.cat", Some win7_64;
    "drivers/amd64/Win7/netkvm.cat", Some win7_64;
    "drivers/amd64/Win7/vioscsi.inf", Some win7_64;
    "drivers/amd64/Win2003/viostor.inf", Some win2k3_64;
    "drivers/amd64/Win2003/viostor.sys", Some win2k3_64;
    "drivers/amd64/Win2003/netkvm.inf", Some win2k3_64;
    "drivers/amd64/Win2003/netkvm.sys", Some win2k3_64;
    "drivers/amd64/Win2003/viostor.cat", Some win2k3_64;
    "drivers/amd64/Win2003/netkvm.cat", Some win2k3_64;
    "drivers/amd64/Win8/viostor.inf", Some win8_64;
    "drivers/amd64/Win8/viostor.sys", Some win8_64;
    "drivers/amd64/Win8/vioscsi.cat", Some win8_64;
    "drivers/amd64/Win8/netkvm.inf", Some win8_64;
    "drivers/amd64/Win8/netkvm.sys", Some win8_64;
    "drivers/amd64/Win8/viostor.cat", Some win8_64;
    "drivers/amd64/Win8/vioscsi.sys", Some win8_64;
    "drivers/amd64/Win8/netkvm.cat", Some win8_64;
    "drivers/amd64/Win8/vioscsi.inf", Some win8_64;
    "drivers/amd64/Win2012/viostor.inf", Some win2k12_64;
    "drivers/amd64/Win2012/viostor.sys", Some win2k12_64;
    "drivers/amd64/Win2012/vioscsi.cat", Some win2k12_64;
    "drivers/amd64/Win2012/netkvm.inf", Some win2k12_64;
    "drivers/amd64/Win2012/netkvm.sys", Some win2k12_64;
    "drivers/amd64/Win2012/viostor.cat", Some win2k12_64;
    "drivers/amd64/Win2012/vioscsi.sys", Some win2k12_64;
    "drivers/amd64/Win2012/netkvm.cat", Some win2k12_64;
    "drivers/amd64/Win2012/vioscsi.inf", Some win2k12_64;
    "drivers/amd64/Win2008R2/viostor.inf", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/viostor.sys", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/qxldd.dll", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/qxl.sys", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/vioscsi.cat", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/netkvm.inf", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/netkvm.sys", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/viostor.cat", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/qxl.inf", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/vioscsi.sys", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/qxl.cat", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/netkvm.cat", Some win2k8r2_64;
    "drivers/amd64/Win2008R2/vioscsi.inf", Some win2k8r2_64;
    "drivers/amd64/Win2012R2/viostor.inf", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/viostor.sys", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/vioscsi.cat", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/netkvm.inf", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/netkvm.sys", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/viostor.cat", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/vioscsi.sys", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/netkvm.cat", Some win2k12r2_64;
    "drivers/amd64/Win2012R2/vioscsi.inf", Some win2k12r2_64;
    "virtio-win-1.7.4_x86.vfd", None;
  ] in

  (* Test each path against each version of Windows. *)
  let printer = string_of_bool in

  List.iter (
    fun (path, correct_windows) ->
      match correct_windows with
      | None ->
         List.iter (
           fun win ->
             let msg = sprintf "path %s should not match %s"
                               path win.i_product_name in
             assert_equal ~printer ~msg false
               (Windows_virtio.UNIT_TESTS.virtio_iso_path_matches_guest_os path win)
         ) all_windows
      | Some correct_windows ->
         List.iter (
           fun win ->
             let expected = win = correct_windows in
             let msg =
               if expected then
                 sprintf "path %s should match %s"
                         path win.i_product_name
               else
                 sprintf "path %s should not match %s"
                         path win.i_product_name in
             assert_equal ~printer ~msg expected
               (Windows_virtio.UNIT_TESTS.virtio_iso_path_matches_guest_os path win)
         ) all_windows
  ) paths

let test_shell_unquote ctx =
  let printer = identity in
  assert_equal ~printer "a" (Utils.shell_unquote "a");
  assert_equal ~printer "b" (Utils.shell_unquote "'b'");
  assert_equal ~printer "c" (Utils.shell_unquote "\"c\"");
  assert_equal ~printer "dd" (Utils.shell_unquote "\"dd\"");
  assert_equal ~printer "e\\e" (Utils.shell_unquote "\"e\\\\e\"");
  assert_equal ~printer "f\\" (Utils.shell_unquote "\"f\\\\\"");
  assert_equal ~printer "\\g" (Utils.shell_unquote "\"\\\\g\"");
  assert_equal ~printer "h\\-h" (Utils.shell_unquote "\"h\\-h\"");
  assert_equal ~printer "i`" (Utils.shell_unquote "\"i\\`\"");
  assert_equal ~printer "j\"" (Utils.shell_unquote "\"j\\\"\"")

let test_qemu_img_supports ctx =
  (* No assertion here, we don't know if qemu-img supports the
   * feature, so just run the code and make sure it doesn't crash.
   *)
  ignore (Utils.qemu_img_supports_offset_and_size ())

(* Test the VMX file parser in the Parse_vmx module. *)
let test_vmx_parse_string ctx =
  let cmp = Parse_vmx.equal in
  let printer = Parse_vmx.to_string 0 in

  (* This should be identical to the empty file. *)
  let t = Parse_vmx.parse_string "\
test.foo = \"a\"
test.bar = \"b\"
test.present = \"FALSE\"
" in
  assert_equal ~cmp ~printer Parse_vmx.empty t;

  (* Test weird escapes. *)
  let t1 = Parse_vmx.parse_string "\
foo = \"a|20|21b\"
" in
  let t2 = Parse_vmx.parse_string "\
foo = \"a !b\"
" in
  assert_equal ~cmp ~printer t1 t2;

  (* Test case insensitivity. *)
  let t1 = Parse_vmx.parse_string "\
foo = \"abc\"
" in
  let t2 = Parse_vmx.parse_string "\
fOO = \"abc\"
" in
  assert_equal ~cmp ~printer t1 t2;
  let t = Parse_vmx.parse_string "\
flag = \"true\"
" in
  assert_bool "parse_vmx: failed case insensitivity test for booleans #1"
              (Parse_vmx.get_bool t ["FLAG"] = Some true);
  let t = Parse_vmx.parse_string "\
flag = \"TRUE\"
" in
  assert_bool "parse_vmx: failed case insensitivity test for booleans #2"
              (Parse_vmx.get_bool t ["Flag"] = Some true);

  (* Missing keys. *)
  let t = Parse_vmx.parse_string "\
foo = \"a\"
" in
  assert_bool "parse_vmx: failed missing key test"
              (Parse_vmx.get_string t ["bar"] = None);

  (* namespace_present function *)
  let t = Parse_vmx.parse_string "\
foo.bar.present = \"TRUE\"
foo.baz.present = \"FALSE\"
foo.a.b = \"abc\"
foo.a.c = \"abc\"
foo.b = \"abc\"
foo.c.a = \"abc\"
foo.c.b = \"abc\"
" in
 assert_bool "parse_vmx: namespace_present #1"
             (Parse_vmx.namespace_present t ["foo"] = true);
 assert_bool "parse_vmx: namespace_present #2"
             (Parse_vmx.namespace_present t ["foo"; "bar"] = true);
 assert_bool "parse_vmx: namespace_present #3"
             (* this whole namespace should have been culled *)
             (Parse_vmx.namespace_present t ["foo"; "baz"] = false);
 assert_bool "parse_vmx: namespace_present #4"
             (Parse_vmx.namespace_present t ["foo"; "a"] = true);
 assert_bool "parse_vmx: namespace_present #5"
             (* this is a key, not a namespace *)
             (Parse_vmx.namespace_present t ["foo"; "a"; "b"] = false);
 assert_bool "parse_vmx: namespace_present #6"
             (Parse_vmx.namespace_present t ["foo"; "b"] = false);
 assert_bool "parse_vmx: namespace_present #7"
             (Parse_vmx.namespace_present t ["foo"; "c"] = true);
 assert_bool "parse_vmx: namespace_present #8"
             (Parse_vmx.namespace_present t ["foo"; "d"] = false);

 (* map function *)
  let t = Parse_vmx.parse_string "\
foo.bar.present = \"TRUE\"
foo.baz.present = \"FALSE\"
foo.a.b = \"abc\"
foo.a.c = \"abc\"
foo.b = \"abc\"
foo.c.a = \"abc\"
foo.c.b = \"abc\"
" in
  let xs =
    Parse_vmx.map (
      fun path ->
        let path = String.concat "." path in
        function
        | None -> sprintf "%s.present = \"true\"\n" path
        | Some v -> sprintf "%s = \"%s\"\n" path v
    ) t in
  let xs = List.sort compare xs in
  let s = String.concat "" xs in
  assert_equal ~printer:identity "\
foo.a.b = \"abc\"
foo.a.c = \"abc\"
foo.a.present = \"true\"
foo.b = \"abc\"
foo.bar.present = \"TRUE\"
foo.bar.present = \"true\"
foo.c.a = \"abc\"
foo.c.b = \"abc\"
foo.c.present = \"true\"
foo.present = \"true\"
" s;

  (* select_namespaces function *)
  let t1 = Parse_vmx.parse_string "\
foo.bar.present = \"TRUE\"
foo.a.b = \"abc\"
foo.a.c = \"abc\"
foo.b = \"abc\"
foo.c.a = \"abc\"
foo.c.b = \"abc\"
" in
  let t2 =
    Parse_vmx.select_namespaces
      (function ["foo"] -> true | _ -> false) t1 in
  assert_equal ~cmp ~printer t1 t2;

  let t1 = Parse_vmx.parse_string "\
foo.bar.present = \"TRUE\"
foo.a.b = \"abc\"
foo.a.c = \"abc\"
foo.b = \"abc\"
foo.c.a = \"abc\"
foo.c.b = \"abc\"
foo.c.c.d.e.f = \"abc\"
" in
  let t1 =
    Parse_vmx.select_namespaces
      (function ["foo"; "a"] -> true | _ -> false) t1 in
  let t2 = Parse_vmx.parse_string "\
foo.a.b = \"abc\"
foo.a.c = \"abc\"
" in
  assert_equal ~cmp ~printer t2 t1

(* Suites declaration. *)
let suite =
  "virt-v2v" >:::
    [
      "OVF.get_ostype" >:: test_get_ostype;
      "Utils.drive_name" >:: test_drive_name;
      "Utils.drive_index" >:: test_drive_index;
      "Windows_virtio.virtio_iso_path_matches_guest_os" >::
        test_virtio_iso_path_matches_guest_os;
      "Utils.shell_unquote" >:: test_shell_unquote;
      "Utils.qemu_img_supports" >:: test_qemu_img_supports;
      "Parse_vmx.parse_string" >::test_vmx_parse_string;
    ]

let () =
  run_test_tt_main suite
