(* builder
 * Copyright (C) 2017 SUSE Inc.
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

(* This file tests the Index_parser module. *)

open Printf

open OUnit2

open Std_utils
open Unix_utils
open Tools_utils

let tmpdir =
  let tmpdir = Mkdtemp.temp_dir "guestfs-tests." in
  rmdir_on_exit tmpdir;
  tmpdir

let dummy_sigchecker = Sigchecker.create ~gpg:"gpg"
                                         ~check_signature:false
                                         ~gpgkey:Utils.No_Key
                                         ~tmpdir

let dummy_downloader = Downloader.create ~curl:"do-not-use-curl"
                                         ~cache:None ~tmpdir

(* Utils. *)
let write_entries file entries =
  let chan = open_out (tmpdir // file) in
  List.iter (Index_parser.write_entry chan) entries;
  close_out chan

let read_file file =
  read_whole_file (tmpdir // "out")

let parse_file file =
  let source = { Sources.name = "input";
                 uri = tmpdir // file;
                 gpgkey = Utils.No_Key;
                 proxy = Curl.SystemProxy;
                 format = Sources.FormatNative } in
  let entries = Index_parser.get_index ~downloader:dummy_downloader
                                       ~sigchecker:dummy_sigchecker
                                       source in
  List.map (
    fun (id, e) -> (id, { e with Index.file_uri = Filename.basename e.Index.file_uri })
  ) entries

let format_entries entries =
  let format_entry entry =
    write_entries "out" [entry];
    read_file "out" in
  List.map format_entry entries

let assert_equal_string = assert_equal ~printer:(fun x -> sprintf "\"%s\"" x)
let assert_equal_list formatter =
  let printer = (
    fun x -> "(" ^ (String.escaped (String.concat "," (formatter x))) ^ ")"
  ) in
  assert_equal ~printer

let test_write_complete ctx =
  let entry =
    ("test-id", { Index.printable_name = Some "test_name";
           osinfo = Some "osinfo_data";
           file_uri = "image_path";
           arch = Index.Arch "test_arch";
           signature_uri = None;
           checksums = Some [Checksums.SHA512 "512checksum"];
           revision = Utils.Rev_int 42;
           format = Some "qcow2";
           size = Int64.of_int 123456;
           compressed_size = Some (Int64.of_int 12345);
           expand = Some "/dev/sda1";
           lvexpand = Some "/some/lv";
           notes = [ ("", "Notes split\non several lines\n\n with starting space ") ];
           hidden = false;
           aliases = Some ["alias1"; "alias2"];
           sigchecker = dummy_sigchecker;
           proxy = Curl.SystemProxy }) in

  write_entries "out" [entry];
  let actual = read_file "out" in
  let expected = "[test-id]
name=test_name
osinfo=osinfo_data
file=image_path
arch=test_arch
checksum[sha512]=512checksum
revision=42
format=qcow2
size=123456
compressed_size=12345
expand=/dev/sda1
lvexpand=/some/lv
notes=Notes split
 on several lines
 
  with starting space 
aliases=alias1 alias2

" in
  assert_equal_string expected actual;

  let parsed_entries = parse_file "out" in
  assert_equal_list format_entries [entry] parsed_entries

let suite =
  "builder Index_parser" >:::
    [
      "write.complete" >:: test_write_complete;
    ]

let () =
  run_test_tt_main suite
