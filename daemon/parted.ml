(* guestfs-inspection
 * Copyright (C) 2009-2025 Red Hat Inc.
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

open Scanf
open Printf

open Std_utils

open Utils

include Structs

(* This is almost equivalent to print_partition_table in the C code. The
 * difference is that here we enforce the "BYT;" header internally.
 *)
let print_partition_table_machine_readable device =
  udev_settle ();

  let args = ref [] in
  List.push_back args "-m";
  List.push_back args "-s";
  List.push_back args "--";
  List.push_back args device;
  List.push_back args "unit";
  List.push_back args "b";
  List.push_back args "print";

  let out =
    try command "parted" !args
    with
      (* Translate "unrecognised disk label" into an errno code. *)
      Failure str when String.find str "unrecognised disk label" >= 0 ->
        raise (Unix.Unix_error (Unix.EINVAL, "parted", device ^ ": " ^ str)) in

  udev_settle ();

  (* Split the output into lines. *)
  let out = String.trim out in
  let lines = String.nsplit "\n" out in

  (* lines[0] is "BYT;", lines[1] is the device line,
   * lines[2..] are the partitions themselves.
   *)
  match lines with
  | "BYT;" :: device_line :: lines -> device_line, lines
  | [] | [_] ->
     failwith "too few rows of output from 'parted print' command"
  | _ ->
     failwith "did not see 'BYT;' magic value in 'parted print' command"

let part_list device =
  let _, lines = print_partition_table_machine_readable device in

  List.map (
    fun line ->
      try sscanf line "%d:%LdB:%LdB:%LdB"
                 (fun num start end_ size ->
                   { part_num = Int32.of_int num;
                     part_start = start; part_end = end_; part_size = size })
      with Scan_failure err ->
        failwithf "could not parse row from output of 'parted print' command: %s: %s"
                  line err
  ) lines

let part_get_parttype device =
  let device_line, _ = print_partition_table_machine_readable device in

  (* device_line is something like:
   * "/dev/sda:1953525168s:scsi:512:512:msdos:ATA Hitachi HDT72101;"
   *)
  let fields = String.nsplit ":" device_line in
  match fields with
  | _::_::_::_::_::"loop"::_ -> (* If "loop" return an error (RHBZ#634246). *)
     (* ... Unless parted failed to recognize the fake MBR that mkfs.fat from
      * dosfstools-4.2+ created. In that case, return "msdos" for MBR
      * (RHBZ#1931821).
      *)
     if Utils.has_bogus_mbr device then "msdos"
     else failwithf "%s: not a partitioned device" device
  | _::_::_::_::_::ret::_ -> ret
  | _ ->
     failwithf "%s: cannot parse the output of parted" device

let part_get_mbr_part_type device partnum =
  let parttype = part_get_parttype device in
  let mbr_id = Sfdisk.part_get_mbr_id device partnum in

  (* 0x05 - extended partition.
   * 0x0f - extended partition using BIOS INT 13h extensions.
   *)
  match parttype, partnum, mbr_id with
  | "msdos", (1|2|3|4), (0x05|0x0f) -> "extended"
  | "msdos", (1|2|3|4), _ -> "primary"
  | "msdos", _, _ -> "logical"
  | _, _, _ -> "primary"
