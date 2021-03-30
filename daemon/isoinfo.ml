(* Parse isoinfo or xorriso output.
 * Copyright (C) 2009-2021 Red Hat Inc.
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
open Scanf
open Unix

open Std_utils
open Unix_utils

open Mountable
open Utils

include Structs

type tool = Isoinfo | Xorriso
let tool = ref None

let get_tool () =
  match !tool with
  | Some t -> t
  | None ->
     (* Prefer isoinfo because we've been using that tool for longer. *)
     if Sys.command "isoinfo -version" = 0 then (
       tool := Some Isoinfo;
       Isoinfo
     )
     else if Sys.command "xorriso -version" = 0 then (
       tool := Some Xorriso;
       Xorriso
     )
     else
       failwith "isoinfo or xorriso not available"

(* Default each int field in the struct to -1 and each string to "". *)
let default_iso = {
  iso_system_id = "";
  iso_volume_id = "";
  iso_volume_space_size = -1_l;
  iso_volume_set_size = -1_l;
  iso_volume_sequence_number = -1_l;
  (* This is almost always true for CDs because of the media itself,
   * and is not available from xorriso.
   *)
  iso_logical_block_size = 2048_l;
  iso_volume_set_id = "";
  iso_publisher_id = "";
  iso_data_preparer_id = "";
  iso_application_id = "";
  iso_copyright_file_id = "";
  iso_abstract_file_id = "";
  iso_bibliographic_file_id = "";
  iso_volume_creation_t = -1_L;
  iso_volume_modification_t = -1_L;
  iso_volume_expiration_t = -1_L;
  iso_volume_effective_t = -1_L;
}

(* This is always in a fixed format:
 * "2012 03 16 11:05:46.00"
 * or if the field is not present, then:
 * "0000 00 00 00:00:00.00"
 *)
let parse_isoinfo_date str =
  if str = "0000 00 00 00:00:00.00" ||
     str = "             :  :  .  " then
    -1_L
  else (
    sscanf str "%04d %02d %02d %02d:%02d:%02d"
      (fun tm_year tm_mon tm_mday tm_hour tm_min tm_sec ->
        (* Adjust fields. *)
        let tm_year = tm_year - 1900 in
        let tm_mon = tm_mon - 1 in

        (* Convert to time_t *)
        let tm = { tm_sec; tm_min; tm_hour; tm_mday; tm_mon; tm_year;
                   tm_wday = -1; tm_yday = -1; tm_isdst = false } in
        Int64.of_float (fst (Unix.mktime tm))
      )
  )

let do_isoinfo dev =
  (* --debug is necessary to get additional fields, in particular
   * the date & time fields.
   *)
  let lines = command "isoinfo" ["--debug"; "-d"; "-i"; dev] in
  let lines = String.nsplit "\n" lines in

  let ret = ref default_iso in
  List.iter (
    fun line ->
      let n = String.length line in
      if String.is_prefix line "System id: " then
        ret := { !ret with iso_system_id = String.sub line 11 (n-11) }
      else if String.is_prefix line "Volume id: " then
        ret := { !ret with iso_volume_id = String.sub line 11 (n-11) }
      else if String.is_prefix line "Volume set id: " then
        ret := { !ret with iso_volume_set_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Publisher id: " then
        ret := { !ret with iso_publisher_id = String.sub line 14 (n-14) }
      else if String.is_prefix line "Data preparer id: " then
        ret := { !ret with iso_data_preparer_id = String.sub line 18 (n-18) }
      else if String.is_prefix line "Application id: " then
        ret := { !ret with iso_application_id = String.sub line 16 (n-16) }
      else if String.is_prefix line "Copyright File id: " then
        ret := { !ret with iso_copyright_file_id = String.sub line 19 (n-19) }
      else if String.is_prefix line "Abstract File id: " then
        ret := { !ret with iso_abstract_file_id = String.sub line 18 (n-18) }
      else if String.is_prefix line "Bibliographic File id: " then
        ret := { !ret with
                 iso_bibliographic_file_id = String.sub line 23 (n-23) }
      else if String.is_prefix line "Volume size is: " then (
        let i = Int32.of_string (String.sub line 16 (n-16)) in
        ret := { !ret with iso_volume_space_size = i }
      )
      else if String.is_prefix line "Volume set size is: " then (
        let i = Int32.of_string (String.sub line 20 (n-20)) in
        ret := { !ret with iso_volume_set_size = i }
      )
      else if String.is_prefix line "Volume set sequence number is: " then (
        let i = Int32.of_string (String.sub line 31 (n-31)) in
        ret := { !ret with iso_volume_sequence_number = i }
      )
      else if String.is_prefix line "Logical block size is: " then (
        let i = Int32.of_string (String.sub line 23 (n-23)) in
        ret := { !ret with iso_logical_block_size = i }
      )
      else if String.is_prefix line "Creation Date:     " then (
        let t = parse_isoinfo_date (String.sub line 19 (n-19)) in
        ret := { !ret with iso_volume_creation_t = t }
      )
      else if String.is_prefix line "Modification Date: " then (
        let t = parse_isoinfo_date (String.sub line 19 (n-19)) in
        ret := { !ret with iso_volume_modification_t = t }
      )
      else if String.is_prefix line "Expiration Date:   " then (
        let t = parse_isoinfo_date (String.sub line 19 (n-19)) in
        ret := { !ret with iso_volume_expiration_t = t }
      )
      else if String.is_prefix line "Effective Date:    " then (
        let t = parse_isoinfo_date (String.sub line 19 (n-19)) in
        ret := { !ret with iso_volume_effective_t = t }
      )
  ) lines;
  !ret

(* This is always in a fixed format:
 * "2021033012313200"
 * or if the field is not present, then:
 * "0000000000000000"
 * XXX Parse the time zone fields too.
 *)
let parse_xorriso_date str =
  if str = "0000000000000000" then -1_L
  else if String.length str <> 16 then -1_L
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

    (* Convert to time_t *)
    let tm = { tm_sec; tm_min; tm_hour; tm_mday; tm_mon; tm_year;
               tm_wday = -1; tm_yday = -1; tm_isdst = false } in
    Int64.of_float (fst (Unix.mktime tm))
  )

let do_xorriso dev =
  (* stdio: prefix is to work around a stupidity of xorriso. *)
  let lines = command "xorriso" ["-indev"; "stdio:" ^ dev; "-pvd_info"] in
  let lines = String.nsplit "\n" lines in

  let ret = ref default_iso in
  List.iter (
    fun line ->
      let n = String.length line in
      if String.is_prefix line "System Id    : " then
        ret := { !ret with iso_system_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Volume Id    : " then
        ret := { !ret with iso_volume_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Volume Set Id: " then
        ret := { !ret with iso_volume_set_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Publisher Id : " then
        ret := { !ret with iso_publisher_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "App Id       : " then
        ret := { !ret with iso_application_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "CopyrightFile: " then
        ret := { !ret with iso_copyright_file_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Abstract File: " then
        ret := { !ret with iso_abstract_file_id = String.sub line 15 (n-15) }
      else if String.is_prefix line "Biblio File  : " then
        ret := { !ret with
                 iso_bibliographic_file_id = String.sub line 15 (n-15) }
      (* XXX The following fields don't appear to be available
       * with xorriso:
       * - iso_volume_space_size (only available on stderr)
       * - iso_volume_sequence_number
       * - iso_logical_block_size
       *)
      (* XXX xorriso provides a timezone for these fields, but
       * we don't use it here.
       *)
      else if String.is_prefix line "Creation Time: " then (
        let t = parse_xorriso_date (String.sub line 15 (n-15)) in
        ret := { !ret with iso_volume_creation_t = t }
      )
      else if String.is_prefix line "Modif. Time  : " then (
        let t = parse_xorriso_date (String.sub line 15 (n-15)) in
        ret := { !ret with iso_volume_modification_t = t }
      )
      else if String.is_prefix line "Expir. Time  : " then (
        let t = parse_xorriso_date (String.sub line 15 (n-15)) in
        ret := { !ret with iso_volume_expiration_t = t }
      )
      else if String.is_prefix line "Eff. Time    : " then (
        let t = parse_xorriso_date (String.sub line 15 (n-15)) in
        ret := { !ret with iso_volume_effective_t = t }
      )
  ) lines;
  !ret

let isoinfo dev =
  match get_tool () with
  | Isoinfo -> do_isoinfo dev
  | Xorriso -> do_xorriso dev

let isoinfo_device = isoinfo
