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

(** [-i libvirtxml] source. *)

type map_source = string -> string option -> string * string option
(** Map function that takes [path] and [format] parameters, and
    returns the possibly rewritten [qemu_uri, format] pair. *)

val parse_libvirt_xml : verbose:bool -> ?map_source_file:map_source -> ?map_source_dev:map_source -> string -> Types.source
(** Take libvirt XML and parse it into a {!Types.source} structure.

    The optional [?map_source_file] and [?map_source_dev] functions
    are used to map [<source file="..."/>] and [<source dev="..."/>]
    from the XML into QEMU URIs.  If not given, then an identity
    mapping is used.

    This function is also used by {!Input_libvirt}, hence it is
    exported. *)

val input_libvirtxml : bool -> string -> Types.input
(** [input_libvirtxml verbose xml_file] creates and returns a new
    {!Types.input} object specialized for reading input from local
    libvirt XML files. *)
