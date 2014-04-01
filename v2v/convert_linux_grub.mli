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

(** Common code handling grub1 (grub-legacy) and grub2 operations. *)

class type virtual grub = object
  method virtual list_kernels : unit -> string list
  (** Return a list of kernels from the grub configuration.  The
      returned list is a list of filenames. *)
  method virtual configure_console : unit -> unit
  (** Reconfigure the grub console. *)
  method virtual remove_console : unit -> unit
  (** Remove the grub console configuration. *)
end

val grub1 : bool -> Guestfs.guestfs -> Types.inspect -> grub
(** Detect if grub1/grub-legacy is used by this guest and return a
    grub object if so.

    This raises [Failure] if grub1 is not used by this guest or some
    other problem happens. *)

val grub2 : bool -> Guestfs.guestfs -> Types.inspect -> grub
(** Detect if grub2 is used by this guest and return a grub object
    if so.

    This raises [Failure] if grub2 is not used by this guest or some
    other problem happens. *)
