(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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
open Sysprep_gettext.Gettext

module G = Guestfs

let pam_data_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let paths = [ "/var/run/console/*";
                  "/var/run/faillock/*";
                  "/var/run/sepermit/*"; ] in
    List.iter (
      fun path ->
        let files = g#glob_expand path in
        Array.iter (
          fun file ->
            try g#rm file with G.Error _ -> ()
        ) files;
    ) paths;

    []
  )
  else []

let pam_data_op = {
  name = "pam-data";
  enabled_by_default = true;
  heading = s_"Remove the PAM data in the guest";
  pod_description = None;
  extra_args = [];
  perform = pam_data_perform;
}

let () = register_operation pam_data_op
