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

type ovf_flavour =
  | OVirt
  | RHVExportStorageDomain

(** The string representation of available OVF flavours. *)
val ovf_flavours : string list

(** Convert from a string to the corresponding OVF flavour.

    Throw [Invalid_argument] if the string does not match any
    valid flavour. *)
val ovf_flavour_of_string : string -> ovf_flavour

(** Convert an OVF flavour to its string representation. *)
val ovf_flavour_to_string : ovf_flavour -> string

(** Create OVF and related files for RHV.

    The format for RHV export storage domain is described in:
    http://resources.ovirt.org/old-site-files/Ovirt_ovf_format.odt

    The format understood by oVirt has no known documentation.

    OVF isn't a real standard, so it's likely that if we ever had to
    create OVF for another target management system then we would need
    to heavily modify or even duplicate this code. *)

val create_ovf : Types.source -> Types.target list -> Types.guestcaps -> Types.inspect -> Types.output_allocation -> string -> string list -> string list -> string ->  ovf_flavour -> DOM.doc
(** Create the OVF file.

    Actually a {!DOM} document is created, not a file.  It can be written
    to the desired output location using {!DOM.doc_to_chan}. *)

val create_meta_files : Types.output_allocation -> string -> string list -> Types.target list -> string list
(** Create the .meta file associated with each target.

    Note this does not write them, since output_rhv has to do a
    permissions dance when writing files.  Instead the contents of each
    file is returned (one per target), and they must be written to
    [target_file ^ ".meta"]. *)

(**/**)

(* For use by v2v_unit_tests only. *)
val get_ostype : Types.inspect -> string
