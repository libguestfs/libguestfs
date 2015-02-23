(* virt-builder
 * Copyright (C) 2013-2015 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Utils

open Unix
open Printf

let clean_cachedir dir =
  let cmd = sprintf "rm -rf %s" (quote dir) in
  ignore (Sys.command cmd);

type t = {
  verbose : bool;
  directory : string;
}

let create ~verbose ~directory =
  if not (is_directory directory) then
    mkdir_p directory 0o755;
  {
    verbose = verbose;
    directory = directory;
  }

let cache_of_name t name arch revision =
  t.directory // sprintf "%s.%s.%d" name arch revision

let is_cached t name arch revision =
  let filename = cache_of_name t name arch revision in
  Sys.file_exists filename

let print_item_status t ~header l =
  if header then (
    printf (f_"cache directory: %s\n") t.directory
  );
  List.iter (
    fun (name, arch, revision) ->
      let cached = is_cached t name arch revision in
      printf "%-24s %-10s %s\n" name arch
        (if cached then s_"cached" else (*s_*)"no")
  ) l
