(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** Command line argument parsing. *)

module NetTypeAndName : sig
  type t = Types.vnet_type * string option
  (** To find the mapping for a specific named network or bridge, use
      the key [(Network|Bridge, Some name)].  To find the default mapping
      use [(Network|Bridge, None)]. *)
  val compare : t -> t -> int
end
module NetworkMap : sig
  type key = NetTypeAndName.t
  type 'a t = 'a Map.Make(NetTypeAndName).t
  val mem : key -> 'a t -> bool
  val find : key -> 'a t -> 'a
end

type cmdline = {
  compressed : bool;
  debug_overlays : bool;
  do_copy : bool;
  in_place : bool;
  network_map : string NetworkMap.t;
  output_alloc : Types.output_allocation;
  output_format : string option;
  output_name : string option;
  print_source : bool;
  print_target : bool;
  root_choice : Types.root_choice;
}

val parse_cmdline : unit -> cmdline * Types.input * Types.output
