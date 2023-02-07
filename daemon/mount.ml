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

open Std_utils

open Mountable
open Utils

let mount_vfs options vfs mountable mountpoint =
  let mp = Sysroot.sysroot_path mountpoint in

  (* Check the mountpoint exists and is a directory. *)
  if not (is_directory mp) then
    failwithf "mount: %s: mount point is not a directory" mountpoint;

  let args = ref [] in

  (* -o options *)
  (match options, mountable.m_type with
   | "", (MountableDevice | MountablePath) -> ()
   | options, (MountableDevice | MountablePath) ->
      List.push_back args "-o";
      List.push_back args options
   | "", MountableBtrfsVol subvol ->
      List.push_back args "-o";
      List.push_back args ("subvol=" ^ subvol)
   | options, MountableBtrfsVol subvol ->
      List.push_back args "-o";
      List.push_back args ("subvol=" ^ subvol ^ "," ^ options)
  );

  (* -t vfs *)
  (match vfs with
   | "" -> ()
   | t ->
      List.push_back args "-t";
      List.push_back args t
  );

  List.push_back args mountable.m_device;
  List.push_back args mp;

  ignore (command "mount" !args)

let mount = mount_vfs "" ""
let mount_ro = mount_vfs "ro" ""
let mount_options options = mount_vfs options ""
