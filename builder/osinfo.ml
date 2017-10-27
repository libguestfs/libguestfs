(* virt-builder
 * Copyright (C) 2017 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Osinfo_config

let rec fold fn base =
  let locations =
    (* (1) Try the shared osinfo directory, using either the
     * $OSINFO_SYSTEM_DIR envvar or its default value.
     *)
    let dir =
      try Sys.getenv "OSINFO_SYSTEM_DIR"
      with Not_found -> "/usr/share/osinfo" in
    ((dir // "os"), read_osinfo_db_three_levels) ::

      (* (2) Try the libosinfo directory, using the newer three-directory
       * layout ($LIBOSINFO_DB_PATH / "os" / $group-ID / [file.xml]).
       *)
      let path = Osinfo_config.libosinfo_db_path // "os" in
      (path, read_osinfo_db_three_levels) ::

        (* (3) Try the libosinfo directory, using the old flat directory
         * layout ($LIBOSINFO_DB_PATH / "oses" / [file.xml]).
         *)
        let path = Osinfo_config.libosinfo_db_path // "oses" in
        (path, read_osinfo_db_flat) :: [] in


  let files =
    List.flatten (
      filter_map (
          fun (path, f) ->
            if is_directory path then Some (f path)
            (* This is not an error: RHBZ#948324. *)
            else None
      ) locations
  ) in

  List.fold_left fn base files

and read_osinfo_db_three_levels path =
  debug "osinfo: loading 3-level-directories database from %s" path;
  let entries = Array.to_list (Sys.readdir path) in
  let entries = List.map ((//) path) entries in
  (* Iterate only on directories. *)
  let entries = List.filter is_directory entries in
  List.flatten (List.map read_osinfo_db_directory entries)

and read_osinfo_db_flat path =
  debug "osinfo: loading flat database from %s" path;
  read_osinfo_db_directory path

and read_osinfo_db_directory path =
  let entries = Sys.readdir path in
  let entries = Array.to_list entries in
  let entries = List.filter (fun x -> Filename.check_suffix x ".xml") entries in
  let entries = List.map ((//) path) entries in
  let entries = List.filter is_regular_file entries in
  entries
