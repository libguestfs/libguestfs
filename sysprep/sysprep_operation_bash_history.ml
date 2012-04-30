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
open Sysprep_gettext.Gettext

module G = Guestfs

let bash_history_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let files = g#glob_expand "/home/*/.bash_history" in
    Array.iter (
      fun file -> try g#rm file with G.Error _ -> ();
    ) files;
    (try g#rm "/root/.bash_history" with G.Error _ -> ());
    []
  )
  else []

let bash_history_op = {
  name = "bash-history";
  enabled_by_default = true;
  heading = s_"Remove the bash history in the guest";
  pod_description = Some (s_"\
Remove the bash history of user \"root\" and any other users
who have a C<.bash_history> file in their home directory.");
  extra_args = [];
  perform = bash_history_perform;
}

let () = register_operation bash_history_op
