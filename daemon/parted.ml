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

open Scanf

open Std_utils

open Utils

include Structs

(* Test if [sfdisk] is recent enough to have [--part-type], to be used
 * instead of [--print-id] and [--change-id].
 *)
let test_sfdisk_has_part_type = lazy (
  let out = command "sfdisk" ["--help"] in
  String.find out "--part-type" >= 0
)

(* Currently we use sfdisk for getting and setting the ID byte.  In
 * future, extend parted to provide this functionality.  As a result
 * of using sfdisk, this won't work for non-MBR-style partitions, but
 * that limitation is noted in the documentation and we can extend it
 * later without breaking the ABI.
 *)
let part_get_mbr_id device partnum =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  let param =
    if Lazy.force test_sfdisk_has_part_type then
      "--part-type"
    else
      "--print-id" in

  udev_settle ();
  let out =
    command "sfdisk" [param; device; string_of_int partnum] in
  udev_settle ();

  (* It's printed in hex, possibly with a leading space. *)
  sscanf out " %x" identity

(* This is not equivalent to print_partition_table in the C code, as
 * it only deals with the ‘-m’ option output, and it partially parses
 * that.  If we convert other functions that don't use the ‘-m’ version
 * we'll have to refactor this. XXX
 *)
let print_partition_table_machine_readable device =
  udev_settle ();

  let args = ref [] in
  push_back args "-m";
  push_back args "-s";
  push_back args "--";
  push_back args device;
  push_back args "unit";
  push_back args "b";
  push_back args "print";

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

  (* lines[0] is "BYT;", lines[1] is the device line which we ignore,
   * lines[2..] are the partitions themselves.
   *)
  match lines with
  | "BYT;" :: _ :: lines -> lines
  | [] | [_] ->
     failwith "too few rows of output from 'parted print' command"
  | _ ->
     failwith "did not see 'BYT;' magic value in 'parted print' command"

let part_list device =
  let lines = print_partition_table_machine_readable device in

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
