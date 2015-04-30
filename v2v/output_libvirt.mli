(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** [-o libvirt] target. *)

val output_libvirt : bool -> string option -> string -> Types.output
(** [output_libvirt verbose oc output_pool] creates and returns a new
    {!Types.output} object specialized for writing output to
    libvirt. *)

val create_libvirt_xml : ?pool:string -> Types.source -> Types.target list -> Types.guestcaps -> string list -> Types.target_firmware -> DOM.doc
(** This is called from {!Output_local} to generate the libvirt XML. *)
