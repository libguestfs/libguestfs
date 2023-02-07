(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Printf

open Std_utils

let realpath path =
  let chroot = Chroot.create ~name:(sprintf "realpath: %s" path) () in
  Chroot.f chroot Unix_utils.Realpath.realpath path

(* The infamous case_sensitive_path function, which works around
 * the bug in ntfs-3g that all paths are case sensitive even though
 * the underlying filesystem is case insensitive.
 *)
let rec case_sensitive_path path =
  let elems = String.nsplit "/" path in

  (* The caller ensures that the first element of [path] is [/],
   * and therefore the first element of the split list must be
   * empty.
   *)
  assert (List.length elems > 0);
  assert (List.hd elems = "");
  let elems = List.tl elems in

  let chroot =
    Chroot.create ~name:(sprintf "case_sensitive_path: %s" path) () in

  (* Now we iterate down the tree starting at the sysroot. *)
  let elems =
    Chroot.f chroot (
      fun () ->
        let rec loop = function
          | [] -> []
          | [ "."|".." ] ->
             failwithf "path contains \".\" or \"..\" elements"
          | "" :: elems ->
             (* For compatibility with C implementation, we ignore
              * "//" in the middle of the path.
              *)
             loop elems
          | [ file ] ->
             (* If it's the final element, it's allowed to be missing. *)
             (match find_path_element file with
              | None -> [ file ] (* return the original *)
              | Some file -> [ file ]
             );
          | elem :: elems ->
             (match find_path_element elem with
              | None ->
                 failwithf "%s: not found" elem
              | Some elem ->
                 (* This will fail intentionally if not a directory. *)
                 Unix.chdir elem;
                 elem :: loop elems
             )
        in
        loop elems
    ) () in

  (* Reconstruct the case sensitive path. *)
  "/" ^ String.concat "/" elems

and find_path_element name =
  let dir = Sys.readdir "." in
  let dir = Array.to_list dir in
  let lc_name = String.lowercase_ascii name in
  let cmp n = String.lowercase_ascii n = lc_name in
  try Some (List.find cmp dir)
  with Not_found -> None
