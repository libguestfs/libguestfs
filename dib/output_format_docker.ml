(* virt-dib
 * Copyright (C) 2016-2017 Red Hat Inc.
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

let docker_target = ref None
let set_docker_target arg = docker_target := Some arg

let docker_check () =
  require_tool "docker";
  if !docker_target = None then
    error (f_"docker: a target was not specified, use '--docker-target'")

let docker_run_fs (g : Guestfs.guestfs) _ temp_dir =
  let docker_target =
    match !docker_target with
    | None -> assert false (* checked earlier *)
    | Some t -> t in
  message (f_"Importing the image to docker as '%s'") docker_target;
  let dockertmp = Filename.temp_file ~temp_dir "docker." ".tar" in
  g#tar_out ~excludes:[| "./sys/*"; "./proc/*" |] ~xattrs:true ~selinux:true
    "/" dockertmp;
  let cmd = [ "sudo"; "docker"; "import"; dockertmp; docker_target ] in
  if run_command cmd <> 0 then exit 1

let fmt = {
  defaults with
    name = "docker";
    output_to_file = false;
    extra_args = [
      { extra_argspec = [ L"docker-target" ], Getopt.String ("target", set_docker_target), s_"Repo and tag for docker"; };
    ];
    check_prerequisites = Some docker_check;
    run_on_filesystem = Some docker_run_fs;
}

let () = register_format fmt
