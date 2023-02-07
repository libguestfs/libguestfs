(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

val with_augeas : ?name:string -> string list -> (Augeas.t -> 'a) -> 'a
(** Open an Augeas handle, parse only 'configfiles' (these
    files must exist), and then call 'f' with the Augeas handle.

    As a security measure, this bails if any file is too large for
    a reasonable configuration file.  After the call to 'f' the
    Augeas handle is closed. *)

val aug_get_noerrors : Augeas.t -> string -> string option
val aug_matches_noerrors : Augeas.t -> string -> string list
val aug_rm_noerrors : Augeas.t -> string -> int
(** When inspecting a guest, we don't particularly care if Augeas
    calls fail.  These functions wrap {!Augeas.get}, {!Augeas.matches}
    and {!Augeas.rm} returning null content if there is an error. *)

val is_file_nocase : string -> bool
val is_dir_nocase : string -> bool
(** With a filesystem mounted under sysroot, check if [path] is
    a file or directory under that sysroot.  The [path] is
    checked case-insensitively. *)

val is_partition : string -> bool
(** Return true if the device is a partition. *)

val parse_version_from_major_minor : string -> Inspect_types.inspection_data -> unit
(** Make a best effort attempt to parse either X or X.Y from a string,
    usually the product_name string. *)

val with_hive : string -> (Hivex.t -> Hivex.node -> 'a) -> 'a
(** Open a Windows registry "hive", and call the function on the
    handle and root node.

    After the call to the function, the hive is always closed.

    The hive is opened readonly. *)
