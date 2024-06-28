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

open Scanf
open Printf

open Std_utils

open Utils

include Structs

let part_get_mbr_id device partnum =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let out =
    command "sfdisk" ["--part-type"; device; string_of_int partnum] in
  udev_settle ();

  (* It's printed in hex, possibly with a leading space. *)
  sscanf out " %x" identity

let part_get_gpt_type device partnum =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let out =
    command "sfdisk" ["--part-type"; device; string_of_int partnum] in
  udev_settle ();

  String.trimr out

let part_set_gpt_type device partnum typ =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let cmd =
    sprintf "sfdisk --part-type %s %d %s"
      (quote device) partnum (quote typ) in
  if verbose () then eprintf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then failwith "sfdisk --part-type failed";
  udev_settle ()

let part_get_gpt_guid device partnum =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let out =
    command "sfdisk" ["--part-uuid"; device; string_of_int partnum] in
  udev_settle ();

  String.trimr out

let part_set_gpt_guid device partnum guid =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let cmd =
    sprintf "sfdisk --part-uuid %s %d %s"
      (quote device) partnum (quote guid) in
  if verbose () then eprintf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then failwith "sfdisk --part-uuid failed";
  udev_settle ()

let part_get_disk_guid device =
  udev_settle ();
  let out =
    command "sfdisk" ["--disk-id"; device] in
  udev_settle ();

  String.trimr out

let part_set_disk_guid device guid =
  udev_settle ();
  let cmd =
    sprintf "sfdisk --disk-id %s %s"
      (quote device) (quote guid) in
  if verbose () then eprintf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then failwith "sfdisk --disk-id failed";
  udev_settle ()

let part_set_disk_guid_random device =
  let random_uuid = Utils.get_random_uuid () in
  let random_uuid = String.trimr random_uuid in
  part_set_disk_guid device random_uuid

let part_get_gpt_attributes device partnum =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  udev_settle ();
  let out =
    command "sfdisk" ["--part-attrs"; device; string_of_int partnum] in
  udev_settle ();

  let out = String.trimr out in

  (* The output is a whitespace-separated list of:
   *
   * "RequiredPartition" (equivalent to bit 0)
   * "NoBlockIOProtocol" (equivalent to bit 1)
   * "LegacyBIOSBootable" (equivalent to bit 2)
   * "GUID:" followed by a comma-separated list of bit numbers
   *
   * eg: "LegacyBIOSBootable RequiredPartition GUID:48,49"
   *
   * So this is a massive PITA to parse.
   *)
  let rec loop out acc =
    let len = String.length out in
    eprintf "part_get_gpt_attributes: %S [%s]\n%!"
      out (String.concat "," (List.map string_of_int acc));
    if len = 0 then (
      acc
    )
    else if Char.isspace out.[0] then (
      let out = String.triml out in
      loop out acc
    )
    else if out.[0] = ',' then (
      let out = String.sub out 1 (len-1) in
      loop out acc
    )
    else if String.is_prefix out "RequiredPartition" then (
      let acc = 0 :: acc in
      let out = String.sub out 17 (len-17) in
      loop out acc
    )
    else if String.is_prefix out "NoBlockIOProtocol" then (
      let acc = 1 :: acc in
      let out = String.sub out 17 (len-17) in
      loop out acc
    )
    else if String.is_prefix out "LegacyBIOSBootable" then (
      let acc = 2 :: acc in
      let out = String.sub out 18 (len-18) in
      loop out acc
    )
    else if String.is_prefix out "GUID:" then (
      let out = String.sub out 5 (len-5) in
      loop out acc
    )
    else if Char.isdigit out.[0] then (
      let n = String.span out "0123456789" in
      let num, out = String.break n out in
      let bit =
        try int_of_string num
        with Failure _ ->
          failwithf "part_get_gpt_attributes: cannot parse number %S" num in
      let acc = bit :: acc in
      loop out acc
    )
    else (
      failwithf "part_get_gpt_attributes: cannot parse %S" out
    )
  in
  let attrs = loop out [] in

  let bits =
    List.fold_left (
      fun bits bit -> Int64.logor bits (Int64.shift_left 1_L bit)
    ) 0_L attrs in
  eprintf "part_get_gpt_attributes: [%s] -> %Ld\n%!"
    (String.concat "," (List.map string_of_int attrs)) bits;
  bits

let part_set_gpt_attributes device partnum attrs =
  if partnum <= 0 then
    failwith "partition number must be >= 1";

  (* The input to sfdisk --part-attrs is a comma-separated list of
   * attribute names or bit positions.  Note you have to use the
   * names, you can't use "0", "1" or "2".
   *)
  let s = ref [] in
  let rec loop i =
    let b = Int64.logand attrs (Int64.shift_left 1_L i) <> Int64.zero in
    (match i with
     | 0 -> if b then List.push_front "RequiredPartition" s
     | 1 -> if b then List.push_front "NoBlockIOProtocol" s
     | 2 -> if b then List.push_front "LegacyBIOSBootable" s
     | i when i >= 3 && i <= 47 ->
        if b then
          failwith "bits 3..47 are reserved and cannot be set"
     | i when i >= 48 && i <= 63 ->
        if b then List.push_front (string_of_int i) s
     | _ -> assert false
    );
    if i < 63 then loop (i+1)
  in
  loop 0;

  udev_settle ();
  let cmd =
    sprintf "sfdisk --part-attrs %s %d %s"
      (quote device) partnum (quote (String.concat "," !s)) in
  if verbose () then eprintf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then failwith "sfdisk --part-attrs failed";
  udev_settle ()
