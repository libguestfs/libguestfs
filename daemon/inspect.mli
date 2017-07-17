(* guestfs-inspection
 * Copyright (C) 2009-2017 Red Hat Inc.
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

val inspect_os : unit -> Mountable.t list
val inspect_get_roots : unit -> Mountable.t list
val inspect_get_mountpoints : Mountable.t -> (string * Mountable.t) list
val inspect_get_filesystems : Mountable.t -> Mountable.t list
val inspect_get_format : Mountable.t -> string
val inspect_get_type : Mountable.t -> string
val inspect_get_distro : Mountable.t -> string
val inspect_get_package_format : Mountable.t -> string
val inspect_get_package_management : Mountable.t -> string
val inspect_get_product_name : Mountable.t -> string
val inspect_get_product_variant : Mountable.t -> string
val inspect_get_major_version : Mountable.t -> int
val inspect_get_minor_version : Mountable.t -> int
val inspect_get_arch : Mountable.t -> string
val inspect_get_hostname : Mountable.t -> string
val inspect_get_windows_systemroot : Mountable.t -> string
val inspect_get_windows_software_hive : Mountable.t -> string
val inspect_get_windows_system_hive : Mountable.t -> string
val inspect_get_windows_current_control_set : Mountable.t -> string
val inspect_get_drive_mappings : Mountable.t -> (string * string) list
val inspect_is_live : Mountable.t -> bool
val inspect_is_netinst : Mountable.t -> bool
val inspect_is_multipart : Mountable.t -> bool
