(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let bash_history_perform ~verbose ~quiet g root side_effects =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let files = g#glob_expand "/home/*/.bash_history" in
    Array.iter (
      fun file -> try g#rm file with G.Error _ -> ();
    ) files;
    (try g#rm "/root/.bash_history" with G.Error _ -> ());
  )

let op = {
  defaults with
    name = "bash-history";
    enabled_by_default = true;
    heading = s_"Remove the bash history in the guest";
    pod_description = Some (s_"\
Remove the bash history of user \"root\" and any other users
who have a C<.bash_history> file in their home directory.");
    pod_notes = Some (s_"\
Currently this only looks in C</root> and C</home/*> for
home directories, so users with home directories in other
locations won't have the bash history removed.");
    perform_on_filesystems = Some bash_history_perform;
}

let () = register_operation op
