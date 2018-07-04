(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

(* Network, bridge mapping. *)

open Tools_utils
open Common_gettext.Gettext

open Types

type t = {
  (* For networks we use this to map a named network, or use the
   * default network if no named network exists.
   *)
  mutable network_map : string StringMap.t;
  mutable default_network : string option;

  (* Same as above but for bridges. *)
  mutable bridge_map : string StringMap.t;
  mutable default_bridge : string option;
}

let map t nic =
  match nic.s_vnet_type with
  | Network ->
     (try
        let vnet = StringMap.find nic.s_vnet t.network_map in
        { nic with s_vnet = vnet }
      with Not_found ->
           match t.default_network with
           | None -> nic (* no mapping done *)
           | Some default_network -> { nic with s_vnet = default_network }
     )
  | Bridge ->
     (try
        let vnet = StringMap.find nic.s_vnet t.bridge_map in
        { nic with s_vnet = vnet }
      with Not_found ->
           match t.default_bridge with
           | None -> nic (* no mapping done *)
           | Some default_bridge -> { nic with s_vnet = default_bridge }
     )

let create () = {
  network_map = StringMap.empty;
  default_network = None;
  bridge_map = StringMap.empty;
  default_bridge = None
}

let add_network t i o =
  if StringMap.mem i t.network_map then
    error (f_"duplicate -n/--network parameter.  Duplicate mappings specified for network %s.") i;
  t.network_map <- StringMap.add i o t.network_map

let add_default_network t o =
  if t.default_network <> None then
    error (f_"duplicate -n/--network parameter.  Only one default mapping is allowed.");
  t.default_network <- Some o

let add_bridge t i o =
  if StringMap.mem i t.bridge_map then
    error (f_"duplicate -b/--bridge parameter.  Duplicate mappings specified for bridge %s.") i;
  t.bridge_map <- StringMap.add i o t.bridge_map

let add_default_bridge t o =
  if t.default_bridge <> None then
    error (f_"duplicate -b/--bridge parameter.  Only one default mapping is allowed.");
  t.default_bridge <- Some o
