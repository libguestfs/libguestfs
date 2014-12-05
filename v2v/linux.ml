(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

module G = Guestfs

(* Wrappers around aug_init & aug_load which can dump out full Augeas
 * parsing problems when debugging is enabled.
 *)
let rec augeas_init verbose g =
  g#aug_init "/" 1;
  if verbose then augeas_debug_errors g

and augeas_reload verbose g =
  g#aug_load ();
  if verbose then augeas_debug_errors g

and augeas_debug_errors g =
  try
    let errors = g#aug_match "/augeas/files//error" in
    let errors = Array.to_list errors in
    let map =
      List.fold_left (
        fun map error ->
          let detail_paths = g#aug_match (error ^ "//*") in
          let detail_paths = Array.to_list detail_paths in
          List.fold_left (
            fun map path ->
              (* path is "/augeas/files/<filename>/error/<field>".  Put
               * <filename>, <field> and the value of this Augeas field
               * into a map.
               *)
              let i = string_find path "/error/" in
              assert (i >= 0);
              let filename = String.sub path 13 (i-13) in
              let field = String.sub path (i+7) (String.length path - (i+7)) in

              let detail = g#aug_get path in

              let fmap : string StringMap.t =
                try StringMap.find filename map
                with Not_found -> StringMap.empty in
              let fmap = StringMap.add field detail fmap in
              StringMap.add filename fmap map
          ) map detail_paths
      ) StringMap.empty errors in

    let filenames = StringMap.keys map in
    let filenames = List.sort compare filenames in

    List.iter (
      fun filename ->
        printf "augeas failed to parse %s:\n" filename;
        let fmap = StringMap.find filename map in
        (try
           let msg = StringMap.find "message" fmap in
           printf " error \"%s\"" msg
         with Not_found -> ()
        );
        (try
           let line = StringMap.find "line" fmap
           and char = StringMap.find "char" fmap in
           printf " at line %s char %s" line char
         with Not_found -> ()
        );
        (try
           let lens = StringMap.find "lens" fmap in
           printf " in lens %s" lens
         with Not_found -> ()
        );
        printf "\n"
    ) filenames;

    flush stdout
  with
    Guestfs.Error msg -> eprintf "%s: augeas: %s (ignored)\n" prog msg

let install verbose g inspect packages =
  assert false

let remove verbose g inspect packages =
  if packages <> [] then (
    let package_format = inspect.i_package_format in
    match package_format with
    | "rpm" ->
      let cmd = [ "rpm"; "-e" ] @ packages in
      let cmd = Array.of_list cmd in
      ignore (g#command cmd);

      (* Reload Augeas in case anything changed. *)
      augeas_reload verbose g

    | format ->
      error (f_"don't know how to remove packages using %s: packages: %s")
        format (String.concat " " packages)
  )

let file_list_of_package verbose (g : Guestfs.guestfs) inspect app =
  let package_format = inspect.i_package_format in

  match package_format with
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
                  "redhat-based";
              i_major_version = v } when v < 5 -> true
          | _ -> false in
        if is_rhel_lt_5 then
          pkg_name
        else
          sprintf "%ld:%s" app.G.app2_epoch pkg_name
      ) else
        pkg_name in
    let cmd = [| "rpm"; "-ql"; pkg_name |] in
    if verbose then eprintf "%s\n%!" (String.concat " " (Array.to_list cmd));
    let files = g#command_lines cmd in
    let files = Array.to_list files in
    List.sort compare files
  | format ->
    error (f_"don't know how to get list of files from package using %s")
      format

let rec file_owner verbose g inspect path =
  let package_format = inspect.i_package_format in
  match package_format with
  | "rpm" ->
      (* Although it is possible in RPM for multiple packages to own
       * a file, this deliberately only returns one package.
       *)
      let cmd = [| "rpm"; "-qf"; "--qf"; "%{NAME}"; path |] in
      if verbose then eprintf "%s\n%!" (String.concat " " (Array.to_list cmd));
      (try g#command cmd
       with Guestfs.Error msg as exn ->
         if string_find msg "is not owned" >= 0 then
           raise Not_found
         else
           raise exn
      )

  | format ->
    error (f_"don't know how to find file owner using %s") format

and is_file_owned verbose g inspect path =
  try file_owner verbose g inspect path; true
  with Not_found -> false
