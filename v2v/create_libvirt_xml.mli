(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(** Create libvirt XML for [-o libvirt] and [-o local]. *)

val create_libvirt_xml : ?pool:string -> Types.source -> Types.target list ->
                         Types.target_buses ->
                         Types.guestcaps -> string list ->
                         Types.target_firmware ->
                         Types.inspect ->
                         DOM.doc
(** [create_libvirt_xml ?pool source targets target_buses guestcaps
    target_features target_firmware] creates the final libvirt XML
    for the output hypervisor. *)
