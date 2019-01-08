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

class virtual bootloader : object
  method virtual name : string
  (** The name of the bootloader, for debugging messages. *)

  method virtual augeas_device_patterns : string list
  (** A list of Augeas patterns to search for device names when we
      need to rewrite device names (eg. [/dev/hda] to [/dev/vda]). *)

  method virtual list_kernels : string list
  (** Lists all the kernels configured in the bootloader. *)

  method virtual set_default_kernel : string -> unit
  (** Sets the specified vmlinuz path as default bootloader entry. *)

  method set_augeas_configuration : unit -> bool
  (** Checks whether the bootloader configuration file is included
      in Augeas load list, and if it is not, then include it.

      Returns true if Augeas needs to be reloaded. *)

  method virtual configure_console : unit -> unit
  method virtual remove_console : unit -> unit
  (** Adds or removes a serial console to all the available kernels. *)

  method update : unit -> unit
  (** Update the bootloader: For grub2 only this runs the
      [grub2-mkconfig] command to rebuild the configuration.  This
      is not necessary for grub-legacy. *)
end
(** Encapsulates a Linux boot loader as object. *)

val detect_bootloader : Guestfs.guestfs -> Types.inspect -> bootloader
(** Detects the bootloader on the guest, and creates the object
    representing it. *)
