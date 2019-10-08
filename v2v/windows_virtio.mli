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

(** Functions for installing Windows virtio drivers. *)

val install_drivers
    : Registry.t -> Types.inspect -> Types.requested_guestcaps ->
      Types.guestcaps_block_type * Types.guestcaps_net_type * Types.guestcaps_video_type * bool * bool * bool
(** [install_drivers reg inspect rcaps]
    installs virtio drivers from the driver directory or driver
    ISO into the guest driver directory and updates the registry
    so that the [viostor.sys] driver gets loaded by Windows at boot.

    [reg] is the system hive which is open for writes when this
    function is called.

    [rcaps] is the set of guest "capabilities" requested by the caller.  This
    may include the type of the block driver, network driver, and video driver.
    install_drivers will adjust its choices based on that information, and
    abort if the requested driver wasn't found.

    This returns the tuple [(block_driver, net_driver, video_driver,
    virtio_rng_supported, virtio_ballon_supported, isa_pvpanic_supported)]
    reflecting what devices are now required by the guest, either
    virtio devices if we managed to install those, or legacy devices
    if we didn't. *)

val install_linux_tools : Guestfs.guestfs -> Types.inspect -> unit
(** installs QEMU Guest Agent on Linux guest OS from the driver directory or
    driver ISO. It is not fatal if we fail to install the agent. *)

val copy_qemu_ga : Guestfs.guestfs -> Types.inspect -> string list
(** copy MSIs (idealy just one) with QEMU Guest Agent to Windows guest. The
    MSIs are not installed by this function. *)

(**/**)

(* The following function is only exported for unit tests. *)
module UNIT_TESTS : sig
  val virtio_iso_path_matches_guest_os : string -> Types.inspect -> bool
end
