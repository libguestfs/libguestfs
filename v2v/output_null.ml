(* virt-v2v
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

open Printf

open Std_utils
open Tools_utils
open Unix_utils
open Common_gettext.Gettext

open Types
open Utils

(* Notes:
 *
 * This only happens to work because we run qemu-img convert
 * with the -n [no create output] option, since null-co doesn't
 * support creation.  If -n is removed in the main program then
 * the tests will break very obviously.
 *
 * The null-co device is not zero-sized.  It actually has a fixed
 * size (defaults to 2^30 I believe).
 *
 * qemu-img convert checks the output size and will fail if it's
 * too small, so we have to set the size.  We could set it to
 * match the input size but it's easier to set it to some huge
 * size instead.
 *)

class output_null =
object
  inherit output

  method as_options = "-o null"

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    let json_params = [
      "file.driver", JSON.String "null-co";
      "file.size", JSON.String "1E";
    ] in
    let target_file = TargetURI ("json:" ^ JSON.string_of_doc json_params) in

    (* While it's not intended that output drivers can set the
     * target_format field (thus overriding the -of option), in
     * this special case of -o null it is reasonable.
     *)
    let target_format = "raw" in

    List.map (fun t -> { t with target_file; target_format }) targets

  method create_metadata _ _ _ _ _ _ = ()
end

let output_null () = new output_null
let () = Modules_list.register_output_module "null"
