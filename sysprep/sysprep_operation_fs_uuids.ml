(* virt-sysprep
 * Copyright (C) 2013 Red Hat Inc.
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

open Sysprep_operation

module G = Guestfs

let rec fs_uuids_perform g root side_effects =
  let fses = g#list_filesystems () in
  List.iter (function
  | _, "unknown" -> ()
  | dev, typ ->
    if not (is_btrfs_subvolume g dev) then (
      let new_uuid = Common_utils.uuidgen () in
      try
        g#set_uuid dev new_uuid
      with
        G.Error msg ->
          warning (f_"cannot set random UUID on filesystem %s type %s: %s")
            dev typ msg
    )
  ) fses

let op = {
  defaults with
    name = "fs-uuids";
    enabled_by_default = false;
    heading = s_"Change filesystem UUIDs";
    pod_description = Some (s_"\
On guests and filesystem types where this is supported,
new random UUIDs are generated and assigned to filesystems.");
    pod_notes = Some (s_"\
The fs-uuids operation is disabled by default because it does
not yet find and update all the places in the guest that use
the UUIDs.  For example C</etc/fstab> or the bootloader.
Enabling this operation is more likely than not to make your
guest unbootable.

See: L<https://bugzilla.redhat.com/show_bug.cgi?id=991641>");
    perform_on_devices = Some fs_uuids_perform;
}

let () = register_operation op
