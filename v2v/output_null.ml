(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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
 *
 * In case neither the null-co driver nor the JSON syntax for URLs
 * is supported, fall back by writing the disks to a temporary
 * directory removed at exit.
 *)

let can_use_qemu_null_co_device () =
  (* We actually attempt to convert a raw file to the null-co device
   * using a JSON URL.
   *)
  let tmp = Filename.temp_file "v2vqemunullcotst" ".img" in
  Unix.truncate tmp 1024;

  let json = [
    "file.driver", JSON.String "null-co";
    "file.size", JSON.String "1E";
  ] in

  let cmd =
    sprintf "qemu-img convert -n -f raw -O raw %s json:%s >/dev/null%s"
            (quote tmp)
            (quote (JSON.string_of_doc ~fmt:JSON.Compact json))
            (if verbose () then "" else " 2>&1") in
  debug "%s" cmd;
  let r = 0 = Sys.command cmd in
  Unix.unlink tmp;
  debug "qemu-img supports the null-co device: %b" r;
  r

class output_null =
  (* Create a temporary directory which is always deleted at exit,
   * so we can put the drives there in case qemu does not support
   * the null-co device w/ a JSON URL.
   *)
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "null." in
    rmdir_on_exit t;
    t in
object
  inherit output

  method as_options = "-o null"

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  (* Force raw output, ignoring -of command line option. *)
  method override_output_format _ = Some "raw"

  method prepare_targets source overlays =
    if can_use_qemu_null_co_device () then (
      let json_params = [
        "file.driver", JSON.String "null-co";
        "file.size", JSON.String "1E";
      ] in
      let target_file = TargetURI ("json:" ^ JSON.string_of_doc json_params) in

      List.map (fun _ -> target_file) overlays
    ) else (
      List.map (fun (_, ov) -> TargetFile (tmpdir // ov.ov_sd)) overlays
    )

  method create_metadata _ _ _ _ _ _ = ()
end

let output_null () = new output_null
let () = Modules_list.register_output_module "null"
