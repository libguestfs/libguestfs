(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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
open Tools_utils
open Common_gettext.Gettext

open Types
open Utils

module G = Guestfs

let augeas_reload g =
  g#aug_load ();
  debug_augeas_errors g

let rec remove g inspect packages =
  if packages <> [] then (
    do_remove g inspect packages;
    (* Reload Augeas in case anything changed. *)
    augeas_reload g
  )

and do_remove g { i_package_format = package_format } packages =
  assert (List.length packages > 0);
  match package_format with
  | "deb" ->
    let cmd = [ "dpkg"; "--purge" ] @ packages in
    let cmd = Array.of_list cmd in
    ignore (g#command cmd);

  | "rpm" ->
    let cmd = [ "rpm"; "-e" ] @ packages in
    let cmd = Array.of_list cmd in
    ignore (g#command cmd)

  | format ->
    error (f_"don’t know how to remove packages using %s: packages: %s")
      format (String.concat " " packages)

let file_list_of_package (g : Guestfs.guestfs) inspect app =
  match inspect.i_package_format with
  | "deb" ->
    let cmd = [| "dpkg"; "-L"; app.G.app2_name |] in
    debug "%s" (String.concat " " (Array.to_list cmd));
    let files = g#command_lines cmd in
    let files = Array.to_list files in
    List.sort compare files

  | "rpm" ->
    (* Since RPM allows multiple packages installed with the same
     * name, always check the full ENVR here (RHBZ#1161250).
     *)
    let pkg_name =
      sprintf "%s-%s-%s" app.G.app2_name
        app.G.app2_version app.G.app2_release in
    let pkg_name =
      if app.G.app2_epoch > 0_l then (
        (* RHEL 3/4 'rpm' does not support using the epoch prefix.
         * (RHBZ#1170685).
         *)
        let is_rhel_lt_5 =
          match inspect with
          | { i_type = "linux";
              i_distro = "rhel" | "centos" | "scientificlinux" |
                  "oraclelinux" | "redhat-based";
              i_major_version = v } when v < 5 -> true
          | _ -> false in
        if is_rhel_lt_5 then
          pkg_name
        else
          sprintf "%ld:%s" app.G.app2_epoch pkg_name
      ) else
        pkg_name in
    let cmd = [| "rpm"; "-ql"; pkg_name |] in
    debug "%s" (String.concat " " (Array.to_list cmd));
    let files = g#command_lines cmd in
    let files = Array.to_list files in
    List.sort compare files

  | format ->
    error (f_"don’t know how to get list of files from package using %s")
      format

let rec file_owner (g : G.guestfs) { i_package_format = package_format } path =
  match package_format with
  | "deb" ->
      (* With dpkg usually the directories are owned by all the packages
       * that install anything in them.  Also with multiarch the same
       * package is allowed (although with different architectures).
       * This function returns only one package in all the cases.
       *)
      let cmd = [| "dpkg"; "-S"; path |] in
      debug "%s" (String.concat " " (Array.to_list cmd));
      let lines =
        try g#command_lines cmd
        with Guestfs.Error msg as exn ->
          if String.find msg "no path found matching pattern" >= 0 then
            raise Not_found
          else
            raise exn in
      if Array.length lines = 0 then
        error (f_"internal error: file_owner: dpkg command returned no output");
      let line = lines.(0) in
      let line =
        try String.sub line 0 (String.rindex line ':')
        with Invalid_argument _ ->
          error (f_"internal error: file_owner: invalid dpkg output: ‘%s’")
                line in
      fst (String.split "," line)

  | "rpm" ->
      (* Although it is possible in RPM for multiple packages to own
       * a file, this deliberately only returns one package.
       *)
      let cmd = [| "rpm"; "-qf"; "--qf"; "%{NAME}\\n"; path |] in
      debug "%s" (String.concat " " (Array.to_list cmd));
      (try
         let pkgs = g#command_lines cmd in
         pkgs.(0)
       with Guestfs.Error msg as exn ->
         if String.find msg "is not owned" >= 0 then
           raise Not_found
         else
           raise exn
       | Invalid_argument _ (* pkgs.(0) raises index out of bounds *) ->
         error (f_"internal error: file_owner: rpm command returned no output")
      )

  | format ->
    error (f_"don’t know how to find file owner using %s") format

and is_file_owned g inspect path =
  try ignore (file_owner g inspect path); true
  with Not_found -> false

let is_package_manager_save_file filename =
  (* Recognized suffixes of package managers. *)
  let suffixes = [ ".dpkg-old"; ".dpkg-new"; ".rpmsave"; ".rpmnew"; ] in
  List.exists (Filename.check_suffix filename) suffixes
