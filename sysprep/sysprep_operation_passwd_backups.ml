(* virt-sysprep
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

open Printf

open Common_gettext.Gettext
open Sysprep_operation
open Utils

module G = Guestfs

let files = List.sort compare [
  "/etc/group-";
  "/etc/gshadow-";
  "/etc/passwd-";
  "/etc/shadow-";
  "/etc/subuid-";
  "/etc/subgid-";
]
let files_as_pod = pod_of_list files

let passwd_backups_perform (g : Guestfs.guestfs) root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then
    List.iter g#rm_f files

let op = {
  defaults with
    name = "passwd-backups";
    enabled_by_default = true;
    heading = s_"Remove /etc/passwd- and similar backup files";
    pod_description = Some (
      sprintf (f_"\
On Linux the following files are removed:

%s") files_as_pod);
    perform_on_filesystems = Some passwd_backups_perform;
}

let () = register_operation op
