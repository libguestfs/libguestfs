(* virt-customize
 * Copyright (C) 2016 Red Hat Inc.
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

(** SELinux-relabel the filesystem. *)

val relabel : Guestfs.guestfs -> unit
(** Relabel the mounted guestfs filesystem using the current SELinux
    policy that applies to the guest.

    If the guest does not look like it uses SELinux, this does nothing.

    In case relabelling is not possible (since it is an optional
    feature which requires the setfiles(8) program), instead we
    fall back to touching [/.autorelabel]. *)
