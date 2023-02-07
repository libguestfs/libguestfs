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

open Unix

open Utils

(* Convert a non-canonical LV path like /dev/mapper/vg-lv or /dev/dm-0
 * to a canonical one.
 *
 * This is harder than it should be.  A LV device like /dev/VG/LV is
 * really a symlink to a device-mapper device like /dev/dm-0.  However
 * at the device-mapper (kernel) level, nothing is really known about
 * LVM (a userspace concept).  Therefore we use a convoluted method to
 * determine this, by listing out known LVs and checking whether the
 * rdev (major/minor) of the device we are passed matches any of them.
 *
 * Note use of 'stat' instead of 'lstat' so that symlinks are fully
 * resolved.
 *)
let lv_canonical device =
  let stat1 = stat device in
  let lvs = Lvm.lvs () in
  try
    Some (
      List.find (
        fun lv ->
          let stat2 = stat lv in
          stat1.st_rdev = stat2.st_rdev
      ) lvs
    )
  with
  | Not_found -> None
