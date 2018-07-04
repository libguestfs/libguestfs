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

(** Network, bridge mapping. *)

type t                          (** The map. *)

val create : unit -> t
(** Create an empty mapping. *)

val add_network : t -> string -> string -> unit
(** Add a network mapping from C<in> to C<out>.

    Equivalent to the [--network in:out] option. *)

val add_default_network : t -> string -> unit
(** Add a default network mapping.

    Equivalent to the [--network out] option. *)

val add_bridge : t -> string -> string -> unit
(** Add a bridge mapping from C<in> to C<out>.

    Equivalent to the [--bridge in:out] option. *)

val add_default_bridge : t -> string -> unit
(** Add a default bridge mapping.

    Equivalent to the [--bridge out] option. *)

val map : t -> Types.source_nic -> Types.source_nic
(** Apply the mapping to the source NIC, returning the updated
    NIC with possibly modified [s_vnet] field. *)
