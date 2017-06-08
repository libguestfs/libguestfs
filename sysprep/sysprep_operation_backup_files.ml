(* virt-sysprep
 * Copyright (C) 2012-2017 Red Hat Inc.
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
open Common_utils
open Common_gettext.Gettext
open Visit
open Unix_utils.Fnmatch
open Sysprep_operation
open Utils

module G = Guestfs

let unix_whitelist = List.sort compare [
  "/etc";
  "/root";
  "/srv";
  "/tmp";
  "/var";
]
let unix_whitelist_as_pod = pod_of_list unix_whitelist

let globs = List.sort compare [
  "*.bak";
  "*~";
]
let globs_as_pod = pod_of_list globs

let backup_files_perform (g : Guestfs.guestfs) root side_effects =
  (* Unix-like?  If so that only operate on the unix_whitelist
   * filesystems, else operate on everything.
   *)
  let fses =
    if unix_like (g#inspect_get_type root) then unix_whitelist
    else ["/"] in

  List.iter (
    fun fs ->
      if g#is_dir ~followsymlinks:false fs then (
        visit g#ocaml_handle fs (
          fun dir filename { G.st_mode = mode } _ ->
            match dir, filename, mode with
            (* Ignore root directory and non-regular files. *)
            | _, None, _ -> ()
            | _, Some _, mode when not (is_reg mode) -> ()
            | dir, Some filename, _ ->
               (* Check the filename against all of the globs, and if it
                * matches any then delete it.
                *)
               let matching glob = fnmatch glob filename [FNM_NOESCAPE] in
               if List.exists matching globs then (
                 let path = full_path dir (Some filename) in
                 g#rm_f path
               )
        )
      )
  ) fses

let op = {
  defaults with
    name = "backup-files";
    enabled_by_default = true;
    heading = s_"Remove editor backup files from the guest";
    pod_description = Some (
      sprintf (f_"\
The following files are removed from anywhere in the guest
filesystem:

%s

On Linux and Unix operating systems, only the following filesystems
will be examined:

%s") globs_as_pod unix_whitelist_as_pod);
    perform_on_filesystems = Some backup_files_perform;
}

let () = register_operation op
