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

(** Common Linux functions. *)

val augeas_init : bool -> Guestfs.guestfs -> unit
val augeas_reload : bool -> Guestfs.guestfs -> unit
(** Wrappers around [g#aug_init] and [g#aug_load], which (if verbose)
    provide additional debugging information about parsing problems
    that augeas found. *)

val install : bool -> Guestfs.guestfs -> Types.inspect -> string list -> unit
(** Install package(s) from the list in the guest (or ensure they are
    installed). *)

val remove : bool -> Guestfs.guestfs -> Types.inspect -> string list -> unit
(** Uninstall package(s). *)

val file_list_of_package : bool -> Guestfs.guestfs -> Types.inspect -> Guestfs.application2 -> string list
(** Return list of files owned by package. *)

val file_owner : bool -> Guestfs.guestfs -> Types.inspect -> string -> string
(** Return the name of the package that owns a file. *)

val is_file_owned : bool -> Guestfs.guestfs -> Types.inspect -> string -> bool
(** Returns true if the file is owned by an installed package. *)
