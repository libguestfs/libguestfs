(* Parse isoinfo or xorriso output.
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

open Printf
open Unix

open Std_utils

include Structs

(* We treat ISO "strA" and "strD" formats the same way, simply
 * discarding any trailing spaces.
 *)
let iso_parse_strA str =
  let len = String.length str in
  let rec loop len =
    if len > 0 && str.[len-1] = ' ' then loop (len-1) else len
  in
  let len = loop len in
  String.sub str 0 len

let iso_parse_strD = iso_parse_strA

(* These always parse the intX_LSB (little endian) version. *)
let iso_parse_int16 s = s |> int_of_le16 |> Int64.to_int32
let iso_parse_int32 s = s |> int_of_le32 |> Int64.to_int32

(* Parse ISO dec-datetime to a Unix time_t. *)
let iso_parse_datetime str =
  if String.sub str 0 16 = "0000000000000000" then -1_L
  else (
    let tm_year = int_of_string (String.sub str 0 4) in
    let tm_mon = int_of_string (String.sub str 4 2) in
    let tm_mday = int_of_string (String.sub str 6 2) in
    let tm_hour = int_of_string (String.sub str 8 2) in
    let tm_min = int_of_string (String.sub str 10 2) in
    let tm_sec = int_of_string (String.sub str 12 2) in

    (* Adjust fields. *)
    let tm_year = tm_year - 1900 in
    let tm_mon = tm_mon - 1 in

    (* Convert to time_t in UTC timezone. *)
    let tm = { tm_sec; tm_min; tm_hour; tm_mday; tm_mon; tm_year;
               tm_wday = -1; tm_yday = -1; tm_isdst = false } in
    let old_TZ = try Some (getenv "TZ") with Not_found -> None in
    putenv "TZ" "UTC";
    let r = Int64.of_float (fst (mktime tm)) in
    Option.iter (putenv "TZ") old_TZ;

    (* The final byte is a time zone offset from GMT.
     *
     * The documentation of this at
     * https://wiki.osdev.org/ISO_9660#The_Primary_Volume_Descriptor
     * is wrong.  See the ECMA 119 documentation for a correct
     * description.
     *
     * For a disk image which we know was created
     * in BST (GMT+1), this contains 0x4, ie. 4 * 15 mins ahead.
     * We have to subtract this from the gmtime above.
     *)
    let tz = Char.code str.[16] in
    let tz = if tz >= 128 then tz - 256 else tz in
    r -^ (Int64.of_int (tz * 15 * 60))
  )

let isoinfo_device dev =
  let r, pvd =
    with_openfile dev [O_RDONLY] 0 (
        fun fd ->
        ignore (lseek fd 32768 SEEK_SET);
        let pvd = Bytes.create 2048 in
        let r = read fd pvd 0 2048 in
        r, Bytes.to_string pvd
      ) in

  let sub = String.sub pvd in

  (* Check that it looks like an ISO9660 Primary Volume Descriptor.
   * https://wiki.osdev.org/ISO_9660#The_Primary_Volume_Descriptor
   *)
  if r <> 2048 || pvd.[0] <> '\001' || sub 1 5 <> "CD001" then
    failwithf "%s: not an ISO file or CD-ROM" dev;

  (* Parse out the PVD fields. *)
  let iso_system_id = sub 8 32 |> iso_parse_strA in
  let iso_volume_id = sub 40 32 |> iso_parse_strA in
  let iso_volume_space_size = sub 80 4 |> iso_parse_int32 in
  let iso_volume_set_size = sub 120 2 |> iso_parse_int16 in
  let iso_volume_sequence_number = sub 124 2 |> iso_parse_int16 in
  let iso_logical_block_size = sub 128 2 |> iso_parse_int16 in
  let iso_volume_set_id = sub 190 128 |> iso_parse_strD in
  let iso_publisher_id = sub 318 128 |> iso_parse_strA in
  let iso_data_preparer_id = sub 446 128 |> iso_parse_strA in
  let iso_application_id = sub 574 128 |> iso_parse_strA in
  let iso_copyright_file_id = sub 702 37 |> iso_parse_strD in
  let iso_abstract_file_id = sub 739 37 |> iso_parse_strD in
  let iso_bibliographic_file_id = sub 776 37 |> iso_parse_strD in
  let iso_volume_creation_t = sub 813 17 |> iso_parse_datetime in
  let iso_volume_modification_t = sub 830 17 |> iso_parse_datetime in
  let iso_volume_expiration_t = sub 847 17 |> iso_parse_datetime in
  let iso_volume_effective_t = sub 864 17 |> iso_parse_datetime in

  (* Return the struct. *)
  {
    iso_system_id; iso_volume_id; iso_volume_space_size;
    iso_volume_set_size; iso_volume_sequence_number;
    iso_logical_block_size; iso_volume_set_id; iso_publisher_id;
    iso_data_preparer_id; iso_application_id; iso_copyright_file_id;
    iso_abstract_file_id; iso_bibliographic_file_id;
    iso_volume_creation_t; iso_volume_modification_t;
    iso_volume_expiration_t; iso_volume_effective_t;
  }

let isoinfo file =
  let chroot = Chroot.create ~name:(sprintf "isoinfo: %s" file) () in
  Chroot.f chroot isoinfo_device file
