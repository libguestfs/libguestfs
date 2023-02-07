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

open Std_utils

open Mountable
open Utils

(* Unmount everything mounted under /sysroot.
 *
 * We have to unmount in the correct order, so we sort the paths by
 * longest first to ensure that child paths are unmounted by parent
 * paths.
 *
 * This call is more important than it appears at first, because it
 * is widely used by both test and production code in order to
 * get back to a known state (nothing mounted, everything synchronized).
 *)
let rec umount_all () =
  (* This is called from internal_autosync and generally as a cleanup
   * function, and since the umount will definitely fail if any
   * handles are open, we may as well close them.
   *)
  (* XXX
  aug_finalize ();
  hivex_finalize ();
  journal_finalize ();
  *)

  let sysroot = Sysroot.sysroot () in
  let sysroot_len = String.length sysroot in

  let info = read_whole_file "/proc/self/mountinfo" in
  let info = String.nsplit "\n" info in

  let mps = ref [] in
  List.iter (
    fun line ->
      let line = String.nsplit " " line in
      (* The field of interest is the 5th field.  Whitespace is escaped
       * with octal sequences like \040 (for space).
       * See fs/seq_file.c:mangle_path.
       *)
      if List.length line >= 5 then (
        let mp = List.nth line 4 in
        let mp = proc_unmangle_path mp in

        (* Allow a mount directory like "/sysroot" or "/sysroot/..." *)
        if (sysroot_len > 0 && String.is_prefix mp sysroot) ||
           (String.is_prefix mp sysroot &&
            String.length mp > sysroot_len &&
            mp.[sysroot_len] = '/') then
          List.push_front mp mps
      )
  ) info;

  let mps = !mps in
  let mps = List.sort compare_longest_first mps in

  (* Unmount them. *)
  List.iter (
    fun mp -> ignore (command "umount" [mp])
  ) mps

and compare_longest_first s1 s2 =
  let n1 = String.length s1 in
  let n2 = String.length s2 in
  n2 - n1
