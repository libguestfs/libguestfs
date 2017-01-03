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

(** Parse libvirt XML into a {!Types.source} structure. *)

type parsed_disk = {
  p_source_disk : Types.source_disk;    (** Source disk. *)
  p_source : parsed_source;         (** <source dev|file attribute> *)
}
and parsed_source =
| P_source_dev of string             (** <source dev> *)
| P_source_file of string            (** <source file> *)
| P_dont_rewrite                     (** s_qemu_uri is already set. *)

val parse_libvirt_xml : ?conn:string -> string -> Types.source * parsed_disk list
(** Take libvirt XML and parse it into a {!Types.source} structure and a
    list of source disks.

    {b Note} the [source.s_disks] field is an empty list.  The caller
    must map over the parsed disks and update the [source.s_disks] field. *)
