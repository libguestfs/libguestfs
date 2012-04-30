(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

let ssh_hostkeys_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let files = g#glob_expand "/etc/ssh/*_host_*" in
    Array.iter g#rm files;
    []
  )
  else []

let ssh_hostkeys_op = {
  name = "ssh-hostkeys";
  enabled_by_default = true;
  heading = s_"Remove the SSH host keys in the guest";
  pod_description = Some (s_"\
The SSH host keys are regenerated (differently) next time the guest is
booted.

If, after cloning, the guest gets the same IP address, ssh will give
you a stark warning about the host key changing:

 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!");
  extra_args = [];
  perform = ssh_hostkeys_perform;
}

let () = register_operation ssh_hostkeys_op
