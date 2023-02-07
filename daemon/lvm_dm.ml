(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Unix
open Printf

open Std_utils

open Utils

(* List everything in /dev/mapper which *isn't* an LV (RHBZ#688062). *)
let list_dm_devices () =
  let ds = Sys.readdir "/dev/mapper" in
  let ds = Array.to_list ds in
  let ds = List.sort compare ds in

  (* Ignore /dev/mapper/control which is used internally by d-m. *)
  let ds = List.filter ((<>) "control") ds in

  let ds = List.map ((^) "/dev/mapper/") ds in

  (* Only keep devices which are _not_ LVs. *)
  let ds = List.filter (fun d -> Lvm_utils.lv_canonical d = None) ds in
  ds
