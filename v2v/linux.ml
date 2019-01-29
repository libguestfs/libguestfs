(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

let re_version = PCRE.compile "(\\d+)\\.(\\d+)"

let augeas_reload g =
  g#aug_load ();
  debug_augeas_errors g

let rec install_local g { i_package_format = package_format } packages =
  if packages <> [] then (
    match package_format with
    | "rpm" ->
      let cmd = [ "rpm"; "--upgrade"; "-v" ] @ packages in
      let cmd = Array.of_list cmd in
      ignore (g#command cmd)
    | format ->
      error (f_"don’t know how to install packages using %s: packages: %s")
        format (String.concat " " packages)
    (* Reload Augeas in case anything changed. *)
    augeas_reload g
  )

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
     * name, always check the full NEVR here (RHBZ#1161250).
     *
     * In RPM < 4.11 query commands that use the epoch number in the
     * package name did not work.
     *
     * For example:
     * RHEL 6 (rpm 4.8.0):
     *   $ rpm -q tar-2:1.23-11.el6.x86_64
     *   package tar-2:1.23-11.el6.x86_64 is not installed
     * Fedora 20 (rpm 4.11.2):
     *   $ rpm -q tar-2:1.26-30.fc20.x86_64
     *   tar-1.26-30.fc20.x86_64
     *)
    let is_rpm_lt_4_11 () =
      let ver =
        try
          let ver = List.find_map (
            function
            | { G.app2_name = name; G.app2_version = version }
                when name = "rpm" -> Some version
            | _ -> None
          ) inspect.i_apps in
          if PCRE.matches re_version ver then
            (int_of_string (PCRE.sub 1), int_of_string (PCRE.sub 2))
          else
            (0, 0)
        with Not_found ->
          (* 'rpm' not installed? Hmm... *)
          (0, 0) in
      ver < (4, 11)
    in
    let pkg_name =
      if app.G.app2_epoch = Int32.zero || is_rpm_lt_4_11 () then
        sprintf "%s-%s-%s" app.G.app2_name app.G.app2_version
          app.G.app2_release
      else
        sprintf "%s-%ld:%s-%s" app.G.app2_name app.G.app2_epoch
          app.G.app2_version app.G.app2_release in
    let cmd = [| "rpm"; "-ql"; pkg_name |] in
    debug "%s" (String.concat " " (Array.to_list cmd));
    let files = g#command_lines cmd in
    let files = Array.to_list files in
    List.sort compare files

  | format ->
    error (f_"don’t know how to get list of files from package using %s")
      format

let is_file_owned (g : G.guestfs) { i_package_format = package_format } path =
  match package_format with
  | "deb" ->
      (* With dpkg usually the directories are owned by all the packages
       * that install anything in them.  Also with multiarch the same
       * package is allowed (although with different architectures).
       * This function returns only one package in all the cases.
       *)
      let cmd = [| "dpkg"; "-S"; path |] in
      debug "%s" (String.concat " " (Array.to_list cmd));
      (try
         let lines = g#command_lines cmd in
         if Array.length lines = 0 then
           error (f_"internal error: is_file_owned: dpkg command returned no output");
         (* Just check the output looks something like "pkg: filename". *)
         if String.find lines.(0) ": " >= 0 then
           true
         else
           error (f_"internal error: is_file_owned: unexpected output from dpkg command: %s")
                 lines.(0)
       with Guestfs.Error msg as exn ->
         if String.find msg "no path found matching pattern" >= 0 then
           false
         else
           raise exn
      )

  | "rpm" ->
     (* Run rpm -qf and print a magic string if the file is owned.
      * If not owned, rpm will print "... is not owned by any package"
      * and exit with an error.  Unfortunately the string is sent to
      * stdout, so here we ignore the exit status of rpm and just
      * look for one of the two strings.
      *)
     let magic = "FILE_OWNED_TEST" in
     let cmd = sprintf "rpm -qf --qf %s %s 2>&1 ||:"
                       (quote (magic ^ "\n")) (quote path) in
     let r = g#sh cmd in
     if String.find r magic >= 0 then true
     else if String.find r "is not owned" >= 0 then false
     else failwithf "RPM file owned test failed: %s" r

  | format ->
    error (f_"don’t know how to find file owner using %s") format

let is_package_manager_save_file filename =
  (* Recognized suffixes of package managers. *)
  let suffixes = [ ".dpkg-old"; ".dpkg-new"; ".rpmsave"; ".rpmnew"; ] in
  List.exists (Filename.check_suffix filename) suffixes
