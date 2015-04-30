(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

class output_null verbose =
  (* It would be nice to be able to write to /dev/null.
   * Unfortunately qemu-img convert cannot do that.  Instead create a
   * temporary directory which is always deleted at exit.
   *)
  let tmpdir =
    let base_dir = (new Guestfs.guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "null." "" in
    rmdir_on_exit t;
    t in
object
  inherit output verbose

  method as_options = "-o null"

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    List.map (
      fun t ->
        let target_file = tmpdir // t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method create_metadata _ _ _ _ _ = ()
end

let output_null = new output_null
let () = Modules_list.register_output_module "null"
