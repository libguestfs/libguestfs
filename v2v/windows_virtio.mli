(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

(** Functions for installing Windows virtio drivers. *)

val install_drivers
    : Guestfs.guestfs -> Types.inspect -> string -> string -> int64 -> string ->
      Types.guestcaps_block_type * Types.guestcaps_net_type * Types.guestcaps_video_type
(** [install_drivers g inspect systemroot virtio_win root current_cs]
    installs virtio drivers from the driver directory or driver
    ISO ([virtio_win]) into the guest driver directory and updates
    the registry so that the [viostor.sys] driver gets loaded by
    Windows at boot.

    [root] is the root node of the system hive (which is open for writes
    when this function is called).  [current_cs] is the name of the
    [CurrentControlSet] (eg. ["ControlSet001"]).

    This returns the tuple [(block_driver, net_driver, video_driver)]
    reflecting what devices are now required by the guest, either
    virtio devices if we managed to install those, or legacy devices
    if we didn't. *)

(**/**)

(* The following function is only exported for unit tests. *)
module UNIT_TESTS : sig
  val virtio_iso_path_matches_guest_os : string -> Types.inspect -> bool
end
