(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

let python = "/usr/libexec/platform-python"

type script = {
  tmpdir : string;              (* Temporary directory. *)
  path : string;                (* Path to script. *)
}

let create ?(name = "script.py") code =
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "v2v." in
    rmdir_on_exit t;
    t in
  let path = tmpdir // name in
  with_open_out path (fun chan -> output_string chan code);
  { tmpdir; path }

let run_command ?echo_cmd ?stdout_fd ?stderr_fd
                { tmpdir; path } params args =
  let param_file = tmpdir // sprintf "params%d.json" (unique ()) in
  with_open_out
    param_file
    (fun chan -> output_string chan (JSON.string_of_doc params));
  Tools_utils.run_command ?echo_cmd ?stdout_fd ?stderr_fd
                          (python :: path :: param_file :: args)

let path { path } = path

let error_unless_python_interpreter_found () =
  try ignore (which python)
  with Executable_not_found _ ->
    error (f_"no python binary called ‘%s’ can be found on the $PATH")
          python
