(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Std_utils
open Types
open Utils

type cols = (string * field) list
type struc = {
  s_name : string;
  s_cols : cols;
  s_camel_name : string;
  s_internal : bool;
  s_unused : unit; (* Silences warning 23 when using 'defaults with ...' *)
}

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

let defaults = { s_name = ""; s_cols = []; s_camel_name = "";
                 s_internal = false; s_unused = () }

(* Names and fields in all structures (in RStruct and RStructList)
 * that we support.
 *)
let structs = [
  (* The old RIntBool return type, only ever used for aug_defnode.  Do
   * not use this struct in any new code.
   *)
  { defaults with
    s_name = "int_bool";
    s_cols = [
    "i", FInt32;		(* for historical compatibility *)
    "b", FInt32;		(* for historical compatibility *)
    ];
    s_camel_name = "IntBool" };

  (* LVM PVs, VGs, LVs. *)
  { defaults with
    s_name = "lvm_pv"; s_cols = lvm_pv_cols; s_camel_name = "PV" };
  { defaults with
    s_name = "lvm_vg"; s_cols = lvm_vg_cols; s_camel_name = "VG" };
  { defaults with
    s_name = "lvm_lv"; s_cols = lvm_lv_cols; s_camel_name = "LV" };

  (* Column names and types from stat structures.
   * NB. Can't use things like 'st_atime' because glibc header files
   * define some of these as macros.  Ugh.
   *)
  { defaults with
    s_name = "stat";
    s_cols = [
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
    s_camel_name = "Stat" };
  (* Because we omitted the nanosecond fields from the above struct,
   * we also have this:
   *)
  { defaults with
    s_name = "statns";
    s_cols = [
    "st_dev", FInt64;
    "st_ino", FInt64;
    "st_mode", FInt64;
    "st_nlink", FInt64;
    "st_uid", FInt64;
    "st_gid", FInt64;
    "st_rdev", FInt64;
    "st_size", FInt64;
    "st_blksize", FInt64;
    "st_blocks", FInt64;
    "st_atime_sec", FInt64;
    "st_atime_nsec", FInt64;
    "st_mtime_sec", FInt64;
    "st_mtime_nsec", FInt64;
    "st_ctime_sec", FInt64;
    "st_ctime_nsec", FInt64;
    "st_spare1", FInt64;
    "st_spare2", FInt64;
    "st_spare3", FInt64;
    "st_spare4", FInt64;
    "st_spare5", FInt64;
    "st_spare6", FInt64;
    ];
    s_camel_name = "StatNS" };
  { defaults with
    s_name = "statvfs";
    s_cols = [
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
    s_camel_name = "StatVFS" };

  (* Column names in dirent structure. *)
  { defaults with
    s_name = "dirent";
    s_cols = [
    "ino", FInt64;
    (* 'b' 'c' 'd' 'f' (FIFO) 'l' 'r' (regular file) 's' 'u' '?' *)
    "ftyp", FChar;
    "name", FString;
    ];
    s_camel_name = "Dirent" };

  (* Version numbers. *)
  { defaults with
    s_name = "version";
    s_cols = [
    "major", FInt64;
    "minor", FInt64;
    "release", FInt64;
    "extra", FString;
    ];
    s_camel_name = "Version" };

  (* Extended attribute. *)
  { defaults with
    s_name = "xattr";
    s_cols = [
    "attrname", FString;
    "attrval", FBuffer;
    ];
    s_camel_name = "XAttr" };

  (* Inotify events. *)
  { defaults with
    s_name = "inotify_event";
    s_cols = [
    "in_wd", FInt64;
    "in_mask", FUInt32;
    "in_cookie", FUInt32;
    "in_name", FString;
    ];
    s_camel_name = "INotifyEvent" };

  (* Partition table entry. *)
  { defaults with
    s_name = "partition";
    s_cols = [
    "part_num", FInt32;
    "part_start", FBytes;
    "part_end", FBytes;
    "part_size", FBytes;
    ];
    s_camel_name = "Partition" };

  (* Application. *)
  { defaults with
    s_name = "application";
    s_cols = [
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
    s_camel_name = "Application" };

  (* Application v2. *)
  { defaults with
    s_name = "application2";
    s_cols = [
    "app2_name", FString;
    "app2_display_name", FString;
    "app2_epoch", FInt32;
    "app2_version", FString;
    "app2_release", FString;
    "app2_arch", FString;
    "app2_install_path", FString;
    "app2_trans_path", FString;
    "app2_publisher", FString;
    "app2_url", FString;
    "app2_source_package", FString;
    "app2_summary", FString;
    "app2_description", FString;
    "app2_spare1", FString;
    "app2_spare2", FString;
    "app2_spare3", FString;
    "app2_spare4", FString;
    ];
    s_camel_name = "Application2" };

  (* ISO primary volume descriptor. *)
  { defaults with
    s_name = "isoinfo";
    s_cols = [
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
    s_camel_name = "ISOInfo" };

  (* /proc/mdstat information.  See linux.git/drivers/md/md.c *)
  { defaults with
    s_name = "mdstat";
    s_cols = [
    "mdstat_device", FString;
    "mdstat_index", FInt32;
    "mdstat_flags", FString;
    ];
    s_camel_name = "MDStat" };

  (* btrfs subvolume list output *)
  { defaults with
    s_name = "btrfssubvolume";
    s_cols = [
    "btrfssubvolume_id", FUInt64;
    "btrfssubvolume_top_level_id", FUInt64;
    "btrfssubvolume_path", FString;
    ];
    s_camel_name = "BTRFSSubvolume" };

  (* btrfs qgroup show output *)
  { defaults with
    s_name = "btrfsqgroup";
    s_cols = [
    "btrfsqgroup_id", FString;
    "btrfsqgroup_rfer", FUInt64;
    "btrfsqgroup_excl", FUInt64;
    ];
    s_camel_name = "BTRFSQgroup" };

  (* btrfs balance status output *)
  { defaults with
    s_name = "btrfsbalance";
    s_cols = [
      "btrfsbalance_status", FString;
      "btrfsbalance_total", FUInt64;
      "btrfsbalance_balanced", FUInt64;
      "btrfsbalance_considered", FUInt64;
      "btrfsbalance_left", FUInt64;
    ];
    s_camel_name = "BTRFSBalance" };

  (* btrfs scrub status output *)
  { defaults with
    s_name = "btrfsscrub";
    s_cols = [
      "btrfsscrub_data_extents_scrubbed", FUInt64;
      "btrfsscrub_tree_extents_scrubbed", FUInt64;
      "btrfsscrub_data_bytes_scrubbed", FUInt64;
      "btrfsscrub_tree_bytes_scrubbed", FUInt64;
      "btrfsscrub_read_errors", FUInt64;
      "btrfsscrub_csum_errors", FUInt64;
      "btrfsscrub_verify_errors", FUInt64;
      "btrfsscrub_no_csum", FUInt64;
      "btrfsscrub_csum_discards", FUInt64;
      "btrfsscrub_super_errors", FUInt64;
      "btrfsscrub_malloc_errors", FUInt64;
      "btrfsscrub_uncorrectable_errors", FUInt64;
      "btrfsscrub_unverified_errors", FUInt64;
      "btrfsscrub_corrected_errors", FUInt64;
      "btrfsscrub_last_physical", FUInt64;
    ];
    s_camel_name = "BTRFSScrub" };

  (* XFS info descriptor. *)
  { defaults with
    s_name = "xfsinfo";
    s_cols = [
    "xfs_mntpoint", FString;
    "xfs_inodesize", FUInt32;
    "xfs_agcount", FUInt32;
    "xfs_agsize", FUInt32;
    "xfs_sectsize", FUInt32;
    "xfs_attr", FUInt32;
    "xfs_blocksize", FUInt32;
    "xfs_datablocks", FUInt64;
    "xfs_imaxpct", FUInt32;
    "xfs_sunit", FUInt32;
    "xfs_swidth", FUInt32;
    "xfs_dirversion", FUInt32;
    "xfs_dirblocksize", FUInt32;
    "xfs_cimode", FUInt32;
    "xfs_logname", FString;
    "xfs_logblocksize", FUInt32;
    "xfs_logblocks", FUInt32;
    "xfs_logversion", FUInt32;
    "xfs_logsectsize", FUInt32;
    "xfs_logsunit", FUInt32;
    "xfs_lazycount", FUInt32;
    "xfs_rtname", FString;
    "xfs_rtextsize", FUInt32;
    "xfs_rtblocks", FUInt64;
    "xfs_rtextents", FUInt64;
    ];
    s_camel_name = "XFSInfo" };

  (* utsname *)
  { defaults with
    s_name = "utsname";
    s_cols = [
    "uts_sysname", FString;
    "uts_release", FString;
    "uts_version", FString;
    "uts_machine", FString;
    ];
    s_camel_name = "UTSName" };

  (* Used by hivex_* APIs to return a list of int64 handles (node
   * handles and value handles).  Note that we can't add a putative
   * 'RInt64List' type to the generator because we need to return
   * length and size, and RStructList does this already.
   *)
  { defaults with
    s_name = "hivex_node";
    s_cols = [
    "hivex_node_h", FInt64;
    ];
    s_camel_name = "HivexNode" };
  { defaults with
    s_name = "hivex_value";
    s_cols = [
    "hivex_value_h", FInt64;
    ];
    s_camel_name = "HivexValue" };
  { defaults with
    s_name = "internal_mountable";
    s_internal = true;
    s_cols = [
    "im_type", FInt32;
    "im_device", FString;
    "im_volume", FString;
    ];
    s_camel_name = "InternalMountable";
  };

  (* The Sleuth Kit directory entry information. *)
  { defaults with
    s_name = "tsk_dirent";
    s_cols = [
    "tsk_inode", FUInt64;
    "tsk_type", FChar;
    "tsk_size", FInt64;
    "tsk_name", FString;
    "tsk_flags", FUInt32;
    "tsk_atime_sec", FInt64;
    "tsk_atime_nsec", FInt64;
    "tsk_mtime_sec", FInt64;
    "tsk_mtime_nsec", FInt64;
    "tsk_ctime_sec", FInt64;
    "tsk_ctime_nsec", FInt64;
    "tsk_crtime_sec", FInt64;
    "tsk_crtime_nsec", FInt64;
    "tsk_nlink", FInt64;
    "tsk_link", FString;
    "tsk_spare1", FInt64;
    ];
    s_camel_name = "TSKDirent" };

  (* Yara detection information. *)
  { defaults with
    s_name = "yara_detection";
    s_cols = [
    "yara_name", FString;
    "yara_rule", FString;
    ];
    s_camel_name = "YaraDetection" };

] (* end of structs *)

let lookup_struct name =
  try List.find (fun { s_name = n } -> n = name) structs
  with Not_found ->
    failwithf
      "lookup_struct: no structs entry corresponding to %s" name

let camel_name_of_struct name = (lookup_struct name).s_camel_name

let cols_of_struct name = (lookup_struct name).s_cols

let compare_structs { s_name = n1 } { s_name = n2 } = compare n1 n2

let external_structs =
  List.sort compare_structs (List.filter (fun x -> not x.s_internal) structs)

let internal_structs =
  List.sort compare_structs (List.filter (fun x -> x.s_internal) structs)
