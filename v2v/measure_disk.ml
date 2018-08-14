(* virt-v2v
 * Copyright (C) 2018 Red Hat Inc.
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
open JSON_parser
open Common_gettext.Gettext

(* Run qemu-img measure on a disk. *)

let measure ?format filename =
  let cmd = ref [] in
  List.push_back_list cmd ["qemu-img"; "measure"];
  (match format with
   | None -> ()
   | Some format ->
      List.push_back_list cmd ["-f"; format]
  );
  (* For use of -O qcow2 here, see this thread:
   * https://www.redhat.com/archives/libguestfs/2018-August/thread.html#00142
   *)
  List.push_back_list cmd ["-O"; "qcow2"];
  List.push_back cmd "--output=json";
  List.push_back cmd filename;

  let json, chan = Filename.open_temp_file "v2vmeasure" ".json" in
  unlink_on_exit json;
  let fd = Unix.descr_of_out_channel chan in
  if run_command ~stdout_fd:fd !cmd <> 0 then
    error (f_"qemu-img measure failed, see earlier errors");
  (* Note that run_command closes fd. *)

  let json = json_parser_tree_parse_file json in
  debug "qemu-img measure output parsed as: %s"
        (JSON.string_of_doc ~fmt:JSON.Indented ["", json]);

  (* We're expecting the tree to contain nodes:
   * Dict [ "required", Int number; "fully-allocated", Int number ]
   * Of course the array could appear in any order.
   *)
  object_get_number "required" json
