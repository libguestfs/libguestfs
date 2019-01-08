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

(** Helper functions for dealing with the OVA pseudo-format. *)

type t

val parse_ova : string -> t
(** The parameter references either an OVA file or a directory
    containing an unpacked OVA.

    The OVA is "opened".  If necessary, parts of the OVA are
    unpacked into a temporary directory.  This can consume a lot
    of space, although we are able to optimize some common cases.

    This does {b not} parse or verify the OVF, MF or disks. *)

val get_ovf_file : t -> string
(** Return the filename of the OVF file from the OVA.  This will
    be a local file (might be a temporary file) valid for the
    lifetime of the handle.

    The filename can be passed directly to
    {!Parse_ovf_from_ova.parse_ovf_from_ova}. *)

type file_ref =
  | LocalFile of string         (** A local filename. *)
  | TarFile of string * string  (** Tar file containing file. *)
(** A file reference, pointing usually to a disk.  If the OVA
    is unpacked during parsing then this points to a local file.
    It might be a temporary file, but it is valid for the lifetime
    of the handle.  If we are optimizing access to the OVA then
    it might also be a reference to a file within a tarball. *)

type mf_record = file_ref * Checksums.csum_t
(** A manifest record: (file reference, checksum of file). *)

val get_manifest : t -> mf_record list
(** Find and parse all manifest ([*.mf]) files in the OVA.
    Parse out the filenames and checksums from these files
    and return the full manifest as a single list.

    Note the checksums are returned, but this function does not
    verify them.  Also VMware-generated OVAs can return
    non-existent files in this list. *)

val get_file_list : t -> file_ref list
(** List the files actually found in the OVA file.  This
    can be different from the manifest (which is often
    incorrect). *)

val resolve_href : t -> string -> file_ref option
(** Resolve an OVF [href] into an actual file reference.  Returns [None]
    if the file does not exist. *)

val get_tar_offet_and_size : string -> string -> int64 * int64
(** [get_tar_offet_and_size tar filename] looks up file in the [tar]
    archive and returns a tuple containing at which byte it starts
    and how long the file is.

    Function raises [Not_found] if there is no such file inside [tar] and
    [Failure] if there is any error parsing the tar output. *)
