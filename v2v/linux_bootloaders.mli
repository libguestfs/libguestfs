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

class virtual bootloader : object
  method virtual name : string
  (** The name of the bootloader. *)
  method virtual augeas_device_patterns : string list
  (** A list of Augeas patterns to search for device names. *)
  method virtual list_kernels : string list
  (** Lists all the kernels configured in the bootloader. *)
  method virtual set_default_kernel : string -> unit
  (** Sets the specified vmlinuz path as default bootloader entry. *)
  method set_augeas_configuration : unit -> bool
  (** Checks whether Augeas is reading the configuration file
      of the bootloader, and if not then add it.

      Returns whether Augeas needs to be reloaded. *)
  method virtual configure_console : unit -> unit
  (** Sets up the console for the available kernels. *)
  method virtual remove_console : unit -> unit
  (** Removes the console in all the available kernels. *)
  method update : unit -> unit
  (** Update the bootloader. *)
end
(** Encapsulates a Linux boot loader as object. *)

val detect_bootloader : Guestfs.guestfs -> Types.inspect -> bootloader
(** Detects the bootloader on the guest, and creates the object
    representing it. *)
