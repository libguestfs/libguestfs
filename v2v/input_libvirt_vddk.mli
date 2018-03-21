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

type vddk_options = {
    vddk_config : string option;
    vddk_cookie : string option;
    vddk_libdir : string option;
    vddk_nfchostport : string option;
    vddk_port : string option;
    vddk_snapshot : string option;
    vddk_thumbprint : string option;
    vddk_transports : string option;
    vddk_vimapiver : string option;
}
(** Various options passed through to the nbdkit vddk plugin unmodified. *)

val input_libvirt_vddk : vddk_options -> string option -> string option -> Xml.uri -> string -> Types.input
(** [input_libvirt_vddk vddk_options password libvirt_uri parsed_uri guest]
    creates and returns a {!Types.input} object specialized for reading
    the guest disks using the nbdkit vddk plugin. *)
