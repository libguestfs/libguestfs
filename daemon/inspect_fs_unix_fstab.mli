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

val check_fstab : ?mdadm_conf:bool -> Mountable.t -> Inspect_types.os_type ->
                  (Mountable.t * string) list
(** [check_fstab] examines the [/etc/fstab] file of a mounted root
    filesystem, returning the list of devices and their mount points.
    Various devices (like CD-ROMs) are ignored in the process, and
    this function also knows how to map (eg) BSD device names into
    Linux/libguestfs device names.

    [mdadm_conf] is true if you want to check [/etc/mdadm.conf] or
    [/etc/mdadm/mdadm.conf] as well.

    [root_mountable] is the [Mountable.t] of the root filesystem.  (Note
    that the root filesystem must be mounted on sysroot before this
    function is called.)

    [os_type] is the presumed operating system type of this root, and
    is used to make some adjustments to fstab parsing. *)
