(* Bindings for visitor function.
 * Copyright (C) 2016 Red Hat Inc.
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

(* This file tests the [Visit] module. *)

open Printf

open C_utils
open Visit

module G = Guestfs

exception Test of string

let rec main () =
  let g = new G.guestfs () in
  g#add_drive_scratch (Int64.mul 1024L (Int64.mul 1024L 1024L));
  g#launch ();

  g#mkfs "ext4" "/dev/sda";
  g#mount_options "user_xattr" "/dev/sda" "/";

  (* Create some files and directories. *)
  g#mkdir "/dir1";
  g#touch "/dir1/file1";
  g#touch "/dir1/file2";
  g#mkdir "/dir2";
  g#mkdir "/dir3";
  g#mkdir "/dir3/dir4";
  g#touch "/dir3/dir4/file6";
  g#setxattr "user.name" "data" 4 "/dir3/dir4/file6";
  g#mkfifo 0o444 "/dir3/dir4/pipe";
  g#touch "/dir3/file3";
  g#touch "/dir3/file4";
  g#mknod_b 0o444 1 2 "/dir3/block";
  g#mknod_c 0o444 1 2 "/dir3/char";

  (* Recurse over them using the visitor function, and check the
   * results.
   *)
  let visited = ref [] in
  visit g#ocaml_handle "/" (
    fun dir filename stat xattrs ->
      if filename <> Some "lost+found" then
        visited := (dir, filename, stat, xattrs) :: !visited
  );
  let visited = List.sort compare !visited in
  let str = string_of_visited visited in
  let expected = "\
/: directory
/dir1: directory
/dir2: directory
/dir3: directory
/dir1/file1: file
/dir1/file2: file
/dir3/block: block device
/dir3/char: char device
/dir3/dir4: directory
/dir3/file3: file
/dir3/file4: file
/dir3/dir4/file6: file user.name=data
/dir3/dir4/pipe: fifo
" in
  if str <> expected then (
    printf "'visit' read these files:\n%s\nexpected these files:\n%s\n"
           str expected;
    exit 1
  );

  (* Recurse over a subdirectory. *)
  let visited = ref [] in
  visit g#ocaml_handle "/dir3" (
    fun dir filename stat xattrs ->
      if filename <> Some "lost+found" then
        visited := (dir, filename, stat, xattrs) :: !visited
  );
  let visited = List.sort compare !visited in
  let str = string_of_visited visited in
  let expected = "\
/dir3: directory
/dir3/block: block device
/dir3/char: char device
/dir3/dir4: directory
/dir3/file3: file
/dir3/file4: file
/dir3/dir4/file6: file user.name=data
/dir3/dir4/pipe: fifo
" in
  if str <> expected then (
    printf "'visit' read these files:\n%s\nexpected these files:\n%s\n"
           str expected;
    exit 1
  );

  (* Raise an exception in the visitor_function. *)
  printf "testing exception in visitor function\n%!";
  (try visit g#ocaml_handle "/" (fun _ _ _ _ -> raise (Test "test"));
       assert false
   with Test "test" -> ()
  (* any other exception escapes and kills the test *)
  );

  (* Force an error and check [Visit.Failure] is raised. *)
  printf "testing general error in visit\n%!";
  (try visit g#ocaml_handle "/nosuchdir" (fun _ _ _ _ -> ());
       assert false
   with Visit.Failure -> ()
  (* any other exception escapes and kills the test *)
  );

  Gc.compact ()

and string_of_visited visited =
  let buf = Buffer.create 1024 in
  List.iter (_string_of_visited buf) visited;
  Buffer.contents buf

and _string_of_visited buf (dir, name, stat, xattrs) =
  let path = full_path dir name in
  bprintf buf "%s: %s%s\n" path (string_of_stat stat) (string_of_xattrs xattrs)

and string_of_stat { G.st_mode = mode } =
  if is_reg mode then "file"
  else if is_dir mode then "directory"
  else if is_chr mode then "char device"
  else if is_blk mode then "block device"
  else if is_fifo mode then "fifo"
  else if is_lnk mode then "link"
  else if is_sock mode then "socket"
  else sprintf "unknown mode 0%Lo" mode

and string_of_xattrs xattrs =
  String.concat "" (List.map string_of_xattr (Array.to_list xattrs))

and string_of_xattr { G.attrname; attrval } =
  sprintf " %s=%s" attrname attrval

let () = main ()
