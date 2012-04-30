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

let ssh_userdir_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let dirs = g#glob_expand "/home/*/.ssh" in
    Array.iter (
      fun dir -> g#rm_rf dir;
    ) dirs;
    g#rm_rf "/root/.ssh";
    []
  )
  else []

let ssh_userdir_op = {
  name = "ssh-userdir";
  enabled_by_default = true;
  heading = s_"Remove \".ssh\" directories in the guest";
  pod_description = Some (s_"\
Remove the C<.ssh> directory of user \"root\" and any other
users who have a C<.ssh> directory in their home directory.");
  extra_args = [];
  perform = ssh_userdir_perform;
}

let () = register_operation ssh_userdir_op
