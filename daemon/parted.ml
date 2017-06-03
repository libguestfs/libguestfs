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
