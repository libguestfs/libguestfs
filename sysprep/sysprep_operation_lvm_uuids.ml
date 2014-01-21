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

open Printf

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let rec lvm_uuids_perform g root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    let has_lvm2_feature =
      try g#available [|"lvm2"|]; true with G.Error _ -> false in
    if has_lvm2_feature then (
      let has_pvs, has_vgs = g#pvs () <> [||], g#vgs () <> [||] in
      if has_pvs || has_vgs then g#vg_activate_all false;
      if has_pvs then g#pvchange_uuid_all ();
      if has_vgs then g#vgchange_uuid_all ();
      if has_pvs || has_vgs then g#vg_activate_all true
    )
  )

let op = {
  defaults with
    name = "lvm-uuids";
    enabled_by_default = true;
    heading = s_"Change LVM2 PV and VG UUIDs";
    pod_description = Some (s_"\
On Linux guests that have LVM2 physical volumes (PVs) or volume groups (VGs),
new random UUIDs are generated and assigned to those PVs and VGs.");
    perform_on_devices = Some lvm_uuids_perform;
}

let () = register_operation op
