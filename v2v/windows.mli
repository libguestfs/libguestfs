(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

(** Common Windows functions. *)

val detect_antivirus : Types.inspect -> bool
(** Return [true] if anti-virus (AV) software was detected in
    this Windows guest. *)

val copy_virtio_drivers : Guestfs.guestfs -> Types.inspect -> string -> string -> bool
(** [copy_virtio_drivers g inspect virtio_win driverdir]
    copies applicable virtio drivers from the driver directory or
    driver ISO into the guest driver dir.  Returns [true] if any
    drivers were copied, or [false] if no suitable drivers were
    found. *)

val with_hive : Guestfs.guestfs -> string -> write:bool -> (int64 -> 'a) -> 'a
(** This is a wrapper that handles opening and closing the hive
    properly around a function [f root].  If [~write] is [true] then
    the hive is opened for writing and committed at the end if the
    function returned without error. *)

(**/**)

(* The following function is only exported for unit tests. *)
module UNIT_TESTS : sig
  val virtio_iso_path_matches_guest_os : string -> Types.inspect -> bool
end
