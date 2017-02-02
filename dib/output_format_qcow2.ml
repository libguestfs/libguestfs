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
open Getopt.OptionName

open Utils
open Output_format

let compressed = ref true
let qemu_img_options = ref None
let set_qemu_img_options arg = qemu_img_options := Some arg

let qcow2_check () =
  require_tool "qemu-img"

let qcow2_run_file filename (tmpdisk, tmpdiskfmt) _ =
  message (f_"Converting to qcow2");
  let cmd = [ "qemu-img"; "convert" ] @
    (if !compressed then [ "-c" ] else []) @
    [ "-f"; tmpdiskfmt; tmpdisk; "-O"; "qcow2" ] @
    (match !qemu_img_options with
    | None -> []
    | Some opt -> [ "-o"; opt ]) @
    [ qemu_input_filename filename ] in
  if run_command cmd <> 0 then exit 1

let fmt = {
  defaults with
    name = "qcow2";
    extra_args = [
      { extra_argspec = [ S 'u' ], Getopt.Clear compressed, s_"Do not compress the qcow2 image"; };
      { extra_argspec = [ L"qemu-img-options" ], Getopt.String ("option", set_qemu_img_options), s_"Add qemu-img options"; };
    ];
    check_prerequisites = Some qcow2_check;
    run_on_file = Some qcow2_run_file;
}

let () = register_format fmt
