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

(** Functions for dealing with OVF files. *)

type ovf_flavour =
  | OVirt
  | RHVExportStorageDomain

val create_meta_files : Types.output_allocation -> string -> string list -> Types.target list -> string list
(** Create the .meta file associated with each target.

    Note this does not write them, since output_rhv has to do a
    permissions dance when writing files.  Instead the contents of each
    file is returned (one per target), and they must be written to
    [target_file ^ ".meta"]. *)

val create_ovf : Types.source -> Types.target list -> Types.guestcaps -> Types.inspect -> Types.output_allocation -> string -> string list -> string list -> string -> ovf_flavour -> DOM.doc
(** Create the OVF file. *)

(**/**)

(* For use by v2v_unit_tests only. *)
val get_ostype : Types.inspect -> string
