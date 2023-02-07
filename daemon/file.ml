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

open Unix
open Printf

open Std_utils

open Utils

(* This runs the [file] command. *)
let file path =
  let is_dev = is_device_parameter path in

  (* For non-dev, check this is a regular file, else just return the
   * file type as a string (RHBZ#582484).
   *)
  if not is_dev then (
    let chroot = Chroot.create ~name:(sprintf "file: %s" path) () in

    let statbuf = Chroot.f chroot lstat path in
    match statbuf.st_kind with
    | S_DIR -> "directory"
    | S_CHR -> "character device"
    | S_BLK -> "block device"
    | S_FIFO -> "FIFO"
    | S_LNK -> "symbolic link"
    | S_SOCK -> "socket"
    | S_REG ->
       (* Regular file, so now run [file] on it. *)
       let out = command "file" ["-zSb"; Sysroot.sysroot_path path] in

       (*  We need to remove the trailing \n from output of file(1).
        *
        * Some upstream versions of file add a space at the end of the
        * output.  This is fixed in the Fedora version, but we might as
        * well fix it here too.  (RHBZ#928995).
        *)
       String.trimr out
  )
  else (* it's a device *) (
    let out = command "file" ["-zSbsL"; path] in
    String.trimr out
  )
