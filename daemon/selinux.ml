(* SELinux functions.
 * Copyright (C) 2009-2025 Red Hat Inc.
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

open Sysroot
open Utils

(* Test if setfiles has various options.
 *
 * The only way to do this is to run setfiles with the option alone, and
 * test for the stderr message [invalid option -- 'X'].
 *)
let setfiles_has_option =
  let test_setfiles flag =
    let err_msg = sprintf "invalid option -- '%c'" flag in
    let opt = sprintf "-%c" flag in
    let _, _, err = commandr "setfiles" [opt] in
    String.find err err_msg = -1
  in
  let h = Hashtbl.create 13 in
  fun flag ->
    try Hashtbl.find h flag
    with
    | Not_found ->
       let r = test_setfiles flag in
       Hashtbl.add h flag r;
       r

let setfiles ?(force = false) specfile paths =
  if paths = [] then ()
  else (
    (* Prefix /sysroot on all paths. *)
    let ignored_paths =
      [ "/dev"; "/proc"; "/selinux"; "/sys" ] |>
      List.map sysroot_path in
    let specfile = sysroot_path specfile in
    let paths = List.map sysroot_path paths in

    let args = ref [] in
    if force then List.push_back args "-F";
    List.iter (
      fun ignored_path ->
        List.push_back_list args [ "-e"; ignored_path ]
    ) ignored_paths;

    (* You have to use the -m option (where available) otherwise
     * setfiles puts all the mountpoints on the excludes list for no
     * useful reason (RHBZ#1433577).
     *)
    if setfiles_has_option 'm' then List.push_back args "-m";

    (* Not only do we want setfiles to trudge through individual relabeling
     * errors, we also want the setfiles exit status to differentiate a fatal
     * error from "relabeling errors only". See RHBZ#1794518.
     *)
    if setfiles_has_option 'C' then List.push_back args "-C";

    (* If the appliance is being run with multiple vCPUs, running setfiles
     * in multithreading mode might speed up the process.  Option "-T" was
     * introduced in SELinux userspace v3.4, and we need to check whether it's
     * supported.  Passing "-T 0" creates as many threads as there're available
     * vCPU cores.
     * https://github.com/SELinuxProject/selinux/releases/tag/3.4
     *)
    if setfiles_has_option 'T' then
      List.push_back_list args [ "-T"; "0" ];

    (* Relabelling in a chroot. *)
    if sysroot () <> "/" then
      List.push_back_list args [ "-r"; sysroot () ];

    if verbose () then
      List.push_back args "-v"
    else
      (* Suppress non-error output. *)
      List.push_back args "-q";

    (* Add parameters. *)
    List.push_back args specfile;
    List.push_back_list args paths;

    let args = !args in
    let r, _, err = commandr "setfiles" args in

    let ok = r = 0 || r = 1 && setfiles_has_option 'C' in
    if not ok then failwithf "setfiles: %s" err
  )

(* This is the deprecated selinux_relabel function from libguestfs <= 1.56. *)
let selinux_relabel ?force specfile path = setfiles ?force specfile [path]
