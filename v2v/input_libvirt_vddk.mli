(* virt-v2v
 * Copyright (C) 2017 Red Hat Inc.
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

(** [-i libvirt] when the source is VMware via nbdkit vddk plugin *)

type vddk_options
(** Various options passed through to the nbdkit vddk plugin unmodified. *)

val print_input_options : unit -> unit
val parse_input_options : (string * string) list -> vddk_options
(** Print and parse vddk -io options. *)

val input_libvirt_vddk : Libvirt.rw Libvirt.Connect.t Lazy.t -> string option -> string option -> vddk_options -> Xml.uri -> string -> Types.input
(** [input_libvirt_vddk libvirt_conn vddk_options parsed_uri guest]
    creates and returns a {!Types.input} object specialized for reading
    the guest disks using the nbdkit vddk plugin. *)
