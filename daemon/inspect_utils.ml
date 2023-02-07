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
open Printf

open Std_utils

open Utils
open Inspect_types

let max_augeas_file_size = 100 * 1000

let rec with_augeas ?name configfiles f =
  let name =
    match name with
    | None -> sprintf "with_augeas: %s" (String.concat " " configfiles)
    | Some name -> name in
  let chroot = Chroot.create ~name () in

  (* Security:
   *
   * The old C code had a few problems: It ignored non-regular-file
   * objects (eg. devices), passing them to Augeas, so relying on
   * Augeas to do the right thing.  Also too-large regular files
   * caused the whole inspection operation to fail.
   *
   * I have tried to improve this so that non-regular files and
   * too large files are ignored (dropped from the configfiles list),
   * so that Augeas won't touch them, but they also won't stop
   * inspection.
   *)
  let safe_file file =
    Is.is_file ~followsymlinks:true file && (
      let size = (Chroot.f chroot Unix.stat file).Unix.st_size in
      size <= max_augeas_file_size
    )
  in
  let configfiles = List.filter safe_file configfiles in

  let aug =
    Augeas.create (Sysroot.sysroot ()) None
                  [Augeas.AugSaveNoop; Augeas.AugNoLoad] in

  protect
    ~f:(fun () ->
      (* Tell Augeas to only load configfiles and no other files.  This
       * prevents a rogue guest from performing a denial of service attack
       * by having large, over-complicated configuration files which are
       * unrelated to the task at hand.  (Thanks Dominic Cleal).
       * Note this requires Augeas >= 1.0.0 because of RHBZ#975412.
       *)
      let pathexpr = make_augeas_path_expression configfiles in
      ignore (aug_rm_noerrors aug pathexpr);
      Augeas.load aug;

      (* Check that augeas did not get a parse error for any of the
       * configfiles, otherwise we are silently missing information.
       *)
      let matches = aug_matches_noerrors aug "/augeas/files//error" in
      List.iter (
        fun match_ ->
          List.iter (
            fun file ->
              let errorpath = sprintf "/augeas/files%s/error" file in
              if match_ = errorpath then (
                (* There's been an error - get the error details. *)
                let get path =
                  match aug_get_noerrors aug (errorpath ^ path) with
                  | None -> "<missing>"
                  | Some v -> v
                in
                let message = get "message" in
                let line = get "line" in
                let charp = get "char" in
                failwithf "%s:%s:%s: augeas parse failure: %s"
                          file line charp message
              )
          ) configfiles
      ) matches;

      f aug
    )
    ~finally:(
      fun () -> Augeas.close aug
    )

(* Explained here: https://bugzilla.redhat.com/show_bug.cgi?id=975412#c0 *)
and make_augeas_path_expression files =
  let subexprs =
    List.map (
      fun file ->
        (*           v NB trailing '/' after filename *)
        sprintf "\"%s/\" !~ regexp('^') + glob(incl) + regexp('/.*')" file
    ) files in
  let subexprs = String.concat " and " subexprs in

  let ret = sprintf "/augeas/load/*[ %s ]" subexprs in
  if verbose () then
    eprintf "augeas pathexpr = %s\n%!" ret;

  ret

and aug_get_noerrors aug path =
  try Augeas.get aug path
  with Augeas.Error _ -> None

and aug_matches_noerrors aug path =
  try Augeas.matches aug path
  with Augeas.Error _ -> []

and aug_rm_noerrors aug path =
  try Augeas.rm aug path
  with Augeas.Error _ -> 0

let is_file_nocase path =
  let path =
    try Some (Realpath.case_sensitive_path path)
    with _ -> None in
  match path with
  | None -> false
  | Some path -> Is.is_file path

and is_dir_nocase path =
  let path =
    try Some (Realpath.case_sensitive_path path)
    with _ -> None in
  match path with
  | None -> false
  | Some path -> Is.is_dir path

(* Rather hairy test for "is a partition", taken directly from
 * the old C inspection code.  XXX fix function and callers
 *)
let is_partition partition =
  try Devsparts.part_to_dev partition <> partition with _ -> false

let re_major_minor = PCRE.compile "(\\d+)\\.(\\d+)"
let re_major_no_minor = PCRE.compile "(\\d+)"

let parse_version_from_major_minor str data =
  if verbose () then
    eprintf "parse_version_from_major_minor: parsing '%s'\n%!" str;

  if PCRE.matches re_major_minor str then (
    let major = int_of_string (PCRE.sub 1) in
    let minor = int_of_string (PCRE.sub 2) in
    data.version <- Some (major, minor)
  )
  else if PCRE.matches re_major_no_minor str then (
    let major = int_of_string (PCRE.sub 1) in
    data.version <- Some (major, 0)
  )
  else (
    eprintf "parse_version_from_major_minor: cannot parse version from '%s'\n"
            str
  )

let with_hive hive_filename f =
  let flags = [] in
  let flags =
    match Daemon_config.hivex_flag_unsafe with
    | None -> flags
    | Some f -> f :: flags in
  let flags = if verbose () then Hivex.OPEN_VERBOSE :: flags else flags in
  let h = Hivex.open_file hive_filename flags in
  protect ~f:(fun () -> f h (Hivex.root h)) ~finally:(fun () -> Hivex.close h)
