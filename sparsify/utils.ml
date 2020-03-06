(* virt-sparsify
 * Copyright (C) 2011-2020 Red Hat Inc.
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

(* Utilities/common functions used in virt-sparsify only. *)

open Printf

open Std_utils

module G = Guestfs

(* Return true if the filesystem is a read-only LV (RHBZ#1185561). *)
let is_read_only_lv (g : G.guestfs) =
  let lvs = Array.to_list (g#lvs_full ()) in
  let ro_uuids = List.filter_map (
    fun { G.lv_uuid; lv_attr } ->
      if lv_attr.[1] = 'r' then Some lv_uuid else None
  ) lvs in
  fun fs ->
    if g#is_lv fs then (
      let uuid = g#lvuuid fs in
      List.exists (fun u -> compare_lvm2_uuids uuid u = 0) ro_uuids
    )
    else false
