(* virt-dib
 * Copyright (C) 2015-2017 Red Hat Inc.
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

open Common_utils
open Common_gettext.Gettext

open Utils
open Output_format

let vhd_check () =
  require_tool "vhd-util"

let vhd_run_file filename (tmpdisk, _) temp_dir =
  message (f_"Converting to VHD");
  let fn_intermediate = Filename.temp_file ~temp_dir "vhd-intermediate." "" in
  let cmd = [ "vhd-util"; "convert"; "-s"; "0"; "-t"; "1";
              "-i"; tmpdisk; "-o"; fn_intermediate ] in
  if run_command cmd <> 0 then exit 1;
  let cmd = [ "vhd-util"; "convert"; "-s"; "1"; "-t"; "2";
              "-i"; fn_intermediate; "-o"; filename ] in
  if run_command cmd <> 0 then exit 1;
  if not (Sys.file_exists filename) then
    error (f_"VHD output not produced, most probably vhd-util is old or not patched for 'convert'")

let fmt = {
  defaults with
    name = "vhd";
    check_prerequisites = Some vhd_check;
    run_on_file = Some vhd_run_file;
}

let () = register_format fmt
