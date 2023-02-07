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

open Utils

(* Test prog_exists. *)
let () =
  assert (prog_exists "ls");
  assert (prog_exists "true")

(* Test command, commandr. *)
let () =
  ignore (command "true" []);

  let r, _, _ = commandr "false" [] in
  assert (r = 1)

(* Test split_device_partition. *)
let () =
  assert (split_device_partition "/dev/sda1" = ("sda", 1));
  assert (split_device_partition "/dev/sdb" = ("sdb", 0));
  assert (split_device_partition "/dev/sdc1" = ("sdc", 1));
  assert (split_device_partition "/dev/sdp1" = ("sdp", 1));  (* RHBZ#1611690 *)
  assert (split_device_partition "/dev/ubda9" = ("ubda", 9));
  assert (split_device_partition "/dev/md0p1" = ("md0", 1))
  (* XXX The function is buggy:
  assert (split_device_partition "/dev/md0" = ("md0", 0)) *)

(* Test proc_unmangle_path. *)
let () =
  assert (proc_unmangle_path "\\040" = " ");
  assert (proc_unmangle_path "\\040\\040" = "  ")

(* Test unix_canonical_path. *)
let () =
  assert (unix_canonical_path "/" = "/");
  assert (unix_canonical_path "/usr" = "/usr");
  assert (unix_canonical_path "/usr/" = "/usr");
  assert (unix_canonical_path "/usr/local" = "/usr/local");
  assert (unix_canonical_path "///" = "/");
  assert (unix_canonical_path "///usr//local//" = "/usr/local");
  assert (unix_canonical_path "/usr///" = "/usr")
