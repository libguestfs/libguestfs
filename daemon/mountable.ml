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

open Printf

type t = {
  m_type : mountable_type;
  m_device : string;
}
and mountable_type =
  | MountableDevice
  | MountablePath
  | MountableBtrfsVol of string (* volume *)

let to_string { m_type = t; m_device = device } =
  match t with
  | MountableDevice | MountablePath -> device
  | MountableBtrfsVol volume ->
     sprintf "btrfsvol:%s/%s" device volume

let of_device device =
  { m_type = MountableDevice; m_device = device }

let of_path path =
  { m_type = MountablePath; m_device = path }

let of_btrfsvol device volume =
  { m_type = MountableBtrfsVol volume; m_device = device }
