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

type t = {
  m_type : mountable_type;
  m_device : string;
}
and mountable_type =
  | MountableDevice
  | MountablePath
  | MountableBtrfsVol of string (* volume *)

val to_string : t -> string
(** Convert the mountable back to the string used in the public API. *)

val of_device : string -> t
val of_path : string -> t
val of_btrfsvol : string -> string -> t
(** Create a mountable from various objects. *)
