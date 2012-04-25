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

open Generator_types
open Generator_utils

type cols = (string * field) list

(* Because we generate extra parsing code for LVM command line tools,
 * we have to pull out the LVM columns separately here.
 *)
let lvm_pv_cols = [
  "pv_name", FString;
  "pv_uuid", FUUID;
  "pv_fmt", FString;
  "pv_size", FBytes;
  "dev_size", FBytes;
  "pv_free", FBytes;
  "pv_used", FBytes;
  "pv_attr", FString (* XXX *);
  "pv_pe_count", FInt64;
  "pv_pe_alloc_count", FInt64;
  "pv_tags", FString;
  "pe_start", FBytes;
  "pv_mda_count", FInt64;
  "pv_mda_free", FBytes;
  (* Not in Fedora 10:
     "pv_mda_size", FBytes;
  *)
]
let lvm_vg_cols = [
  "vg_name", FString;
  "vg_uuid", FUUID;
  "vg_fmt", FString;
  "vg_attr", FString (* XXX *);
  "vg_size", FBytes;
  "vg_free", FBytes;
  "vg_sysid", FString;
  "vg_extent_size", FBytes;
  "vg_extent_count", FInt64;
  "vg_free_count", FInt64;
  "max_lv", FInt64;
  "max_pv", FInt64;
  "pv_count", FInt64;
  "lv_count", FInt64;
  "snap_count", FInt64;
  "vg_seqno", FInt64;
  "vg_tags", FString;
  "vg_mda_count", FInt64;
  "vg_mda_free", FBytes;
  (* Not in Fedora 10:
     "vg_mda_size", FBytes;
  *)
]
let lvm_lv_cols = [
  "lv_name", FString;
  "lv_uuid", FUUID;
  "lv_attr", FString (* XXX *);
  "lv_major", FInt64;
  "lv_minor", FInt64;
  "lv_kernel_major", FInt64;
  "lv_kernel_minor", FInt64;
  "lv_size", FBytes;
  "seg_count", FInt64;
  "origin", FString;
  "snap_percent", FOptPercent;
  "copy_percent", FOptPercent;
  "move_pv", FString;
  "lv_tags", FString;
  "mirror_log", FString;
  "modules", FString;
]

(* Names and fields in all structures (in RStruct and RStructList)
 * that we support.
 *)
let structs = [
  (* The old RIntBool return type, only ever used for aug_defnode.  Do
   * not use this struct in any new code.
   *)
  "int_bool", [
    "i", FInt32;		(* for historical compatibility *)
    "b", FInt32;		(* for historical compatibility *)
  ];

  (* LVM PVs, VGs, LVs. *)
  "lvm_pv", lvm_pv_cols;
  "lvm_vg", lvm_vg_cols;
  "lvm_lv", lvm_lv_cols;

  (* Column names and types from stat structures.
   * NB. Can't use things like 'st_atime' because glibc header files
   * define some of these as macros.  Ugh.
   *)
  "stat", [
    "dev", FInt64;
    "ino", FInt64;
    "mode", FInt64;
    "nlink", FInt64;
    "uid", FInt64;
    "gid", FInt64;
    "rdev", FInt64;
    "size", FInt64;
    "blksize", FInt64;
    "blocks", FInt64;
    "atime", FInt64;
    "mtime", FInt64;
    "ctime", FInt64;
  ];
  "statvfs", [
    "bsize", FInt64;
    "frsize", FInt64;
    "blocks", FInt64;
    "bfree", FInt64;
    "bavail", FInt64;
    "files", FInt64;
    "ffree", FInt64;
    "favail", FInt64;
    "fsid", FInt64;
    "flag", FInt64;
    "namemax", FInt64;
  ];

  (* Column names in dirent structure. *)
  "dirent", [
    "ino", FInt64;
    (* 'b' 'c' 'd' 'f' (FIFO) 'l' 'r' (regular file) 's' 'u' '?' *)
    "ftyp", FChar;
    "name", FString;
  ];

  (* Version numbers. *)
  "version", [
    "major", FInt64;
    "minor", FInt64;
    "release", FInt64;
    "extra", FString;
  ];

  (* Extended attribute. *)
  "xattr", [
    "attrname", FString;
    "attrval", FBuffer;
  ];

  (* Inotify events. *)
  "inotify_event", [
    "in_wd", FInt64;
    "in_mask", FUInt32;
    "in_cookie", FUInt32;
    "in_name", FString;
  ];

  (* Partition table entry. *)
  "partition", [
    "part_num", FInt32;
    "part_start", FBytes;
    "part_end", FBytes;
    "part_size", FBytes;
  ];

  (* Application. *)
  "application", [
    "app_name", FString;
    "app_display_name", FString;
    "app_epoch", FInt32;
    "app_version", FString;
    "app_release", FString;
    "app_install_path", FString;
    "app_trans_path", FString;
    "app_publisher", FString;
    "app_url", FString;
    "app_source_package", FString;
    "app_summary", FString;
    "app_description", FString;
  ];

  (* ISO primary volume descriptor. *)
  "isoinfo", [
    "iso_system_id", FString;
    "iso_volume_id", FString;
    "iso_volume_space_size", FUInt32;
    "iso_volume_set_size", FUInt32;
    "iso_volume_sequence_number", FUInt32;
    "iso_logical_block_size", FUInt32;
    "iso_volume_set_id", FString;
    "iso_publisher_id", FString;
    "iso_data_preparer_id", FString;
    "iso_application_id", FString;
    "iso_copyright_file_id", FString;
    "iso_abstract_file_id", FString;
    "iso_bibliographic_file_id", FString;
    "iso_volume_creation_t", FInt64;
    "iso_volume_modification_t", FInt64;
    "iso_volume_expiration_t", FInt64;
    "iso_volume_effective_t", FInt64;
  ];

  (* /proc/mdstat information.  See linux.git/drivers/md/md.c *)
  "mdstat", [
    "mdstat_device", FString;
    "mdstat_index", FInt32;
    "mdstat_flags", FString;
  ];

  (* btrfs subvolume list output *)
  "btrfssubvolume", [
    "btrfssubvolume_id", FUInt64;
    "btrfssubvolume_top_level_id", FUInt64;
    "btrfssubvolume_path", FString;
  ];
] (* end of structs *)

(* For bindings which want camel case *)
let camel_structs = [
  "int_bool", "IntBool";
  "lvm_pv", "PV";
  "lvm_vg", "VG";
  "lvm_lv", "LV";
  "stat", "Stat";
  "statvfs", "StatVFS";
  "dirent", "Dirent";
  "version", "Version";
  "xattr", "XAttr";
  "inotify_event", "INotifyEvent";
  "partition", "Partition";
  "application", "Application";
  "isoinfo", "ISOInfo";
  "mdstat", "MDStat";
  "btrfssubvolume", "BTRFSSubvolume";
]
let camel_structs = List.sort (fun (_,a) (_,b) -> compare a b) camel_structs

let camel_name_of_struct typ =
  try List.assoc typ camel_structs
  with Not_found ->
    failwithf
      "camel_name_of_struct: no camel_structs entry corresponding to %s" typ

let cols_of_struct typ =
  try List.assoc typ structs
  with Not_found ->
    failwithf "cols_of_struct: unknown struct %s" typ
