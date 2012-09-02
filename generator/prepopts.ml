(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

type optargs = (string * string * string) list

type prepopt = string * string * optargs * string

(* Used for the guestfish -N (prepared disk images) option.
 * Note that the longdescs are indented by 2 spaces.
 *)
let prepopts = [
  ("disk",
   "create a blank disk",
   [ "size", "100M", "the size of the disk image" ],
   "  Create a blank disk, size 100MB (by default).

  The default size can be changed by supplying an optional parameter.");

  ("part",
   "create a partitioned disk",
   [ "size", "100M", "the size of the disk image";
     "partition", "mbr", "partition table type" ],
   "  Create a disk with a single partition.  By default the size of the disk
  is 100MB (the available space in the partition will be a tiny bit smaller)
  and the partition table will be MBR (old DOS-style).

  These defaults can be changed by supplying optional parameters.");

  ("fs",
   "create a filesystem",
   [ "filesystem", "ext2", "the type of filesystem to use";
     "size", "100M", "the size of the disk image";
     "partition", "mbr", "partition table type" ],
   "  Create a disk with a single partition, with the partition containing
  an empty filesystem.  This defaults to creating a 100MB disk (the available
  space in the filesystem will be a tiny bit smaller) with an MBR (old
  DOS-style) partition table and an ext2 filesystem.

  These defaults can be changed by supplying optional parameters.");

  ("lv",
   "create a disk with logical volume",
   [ "name", "/dev/VG/LV", "the name of the VG and LV to use";
     "size", "100M", "the size of the disk image";
     "partition", "mbr", "partition table type" ],
   "  Create a disk with a single partition, set up the partition as an
  LVM2 physical volume, and place a volume group and logical volume
  on there.  This defaults to creating a 100MB disk with the VG and
  LV called /dev/VG/LV.  You can change the name of the VG and LV
  by supplying an alternate name as the first optional parameter.

  Note this does not create a filesystem.  Use 'lvfs' to do that.");

  ("lvfs",
   "create a disk with logical volume and filesystem",
   [ "name", "/dev/VG/LV", "the name of the VG and LV to use";
     "filesystem", "ext2", "the type of filesystem to use";
     "size", "100M", "the size of the disk image";
     "partition", "mbr", "partition table type" ],
   "  Create a disk with a single partition, set up the partition as an
  LVM2 physical volume, and place a volume group and logical volume
  on there.  Then format the LV with a filesystem.  This defaults to
  creating a 100MB disk with the VG and LV called /dev/VG/LV, with an
  ext2 filesystem.");

  ("bootroot",
   "create a boot and root filesystem",
   [ "bootfs", "ext2", "the type of filesystem to use for boot";
     "rootfs", "ext2", "the type of filesystem to use for root";
     "size", "100M", "the size of the disk image";
     "bootsize", "32M", "the size of the boot filesystem";
     "partition", "mbr", "partition table type" ],
   "  Create a disk with two partitions, for boot and root filesystem.
  Format the two filesystems independently.  There are several optional
  parameters which control the exact layout and filesystem types.");

  ("bootrootlv",
   "create a boot and root filesystem using LVM",
   [ "name", "/dev/VG/LV", "the name of the VG and LV for root";
     "bootfs", "ext2", "the type of filesystem to use for boot";
     "rootfs", "ext2", "the type of filesystem to use for root";
     "size", "100M", "the size of the disk image";
     "bootsize", "32M", "the size of the boot filesystem";
     "partition", "mbr", "partition table type" ],
   "  This is the same as 'bootroot' but the root filesystem (only) is
  placed on a logical volume, named by default '/dev/VG/LV'.  There are
  several optional parameters which control the exact layout.");
]
