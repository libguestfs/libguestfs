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

val check_coreos_usr : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the CoreOS [/usr] filesystem mounted on sysroot. *)

val check_coreos_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the CoreOS filesystem mounted on sysroot. *)

val check_freebsd_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the FreeBSD filesystem mounted on sysroot. *)

val check_hurd_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the Hurd filesystem mounted on sysroot. *)

val check_linux_usr : Inspect_types.inspection_data -> unit
(** Inspect the Linux [/usr] filesystem mounted on sysroot. *)

val check_linux_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the Linux filesystem mounted on sysroot. *)

val check_minix_root : Inspect_types.inspection_data -> unit
(** Inspect the Minix filesystem mounted on sysroot. *)

val check_netbsd_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the NetBSD filesystem mounted on sysroot. *)

val check_openbsd_root : Mountable.t -> Inspect_types.inspection_data -> unit
(** Inspect the OpenBSD filesystem mounted on sysroot. *)
