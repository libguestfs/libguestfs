(* virt-sysprep
 * Copyright (C) 2013 Fujitsu Limited.
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

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let tmp_files_perform ~quiet g root side_effects =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let paths = [ "/tmp";
                  "/var/tmp"; ] in
    List.iter (
      fun path ->
        let files = g#glob_expand (path ^ "/*") in
        Array.iter (
          fun file ->
            g#rm_rf file;
        ) files;
        (try
          let files = g#ls path in
          Array.iter (
            fun file ->
              g#rm_rf (path ^ "/" ^ file);
          ) files
        with G.Error _ -> ());
    ) paths
  )

let op = {
  defaults with
    name = "tmp-files";
    enabled_by_default = true;
    heading = s_"Remove temporary files";
    pod_description = Some (s_"\
This removes temporary files under C</tmp> and C</var/tmp>.");
    perform_on_filesystems = Some tmp_files_perform;
}

let () = register_operation op
