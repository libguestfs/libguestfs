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

open Unix_utils

include Structs

let statvfs path =
  let chroot = Chroot.create ~name:(Printf.sprintf "statvfs: %s" path) () in
  let r = Chroot.f chroot StatVFS.statvfs path in

  (* [r : Unix_utils.StatVFS.statvfs] is superficially similar to
   * the guestfs [statvfs] structure, but not the same.  We have to
   * copy the fields.
   *)
  {
    bsize = r.StatVFS.f_bsize;
    frsize = r.StatVFS.f_frsize;
    blocks = r.StatVFS.f_blocks;
    bfree = r.StatVFS.f_bfree;
    bavail = r.StatVFS.f_bavail;
    files = r.StatVFS.f_files;
    ffree = r.StatVFS.f_ffree;
    favail = r.StatVFS.f_favail;
    fsid = r.StatVFS.f_fsid;
    flag = r.StatVFS.f_flag;
    namemax = r.StatVFS.f_namemax;
  }
