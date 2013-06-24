(* virt-sysprep
 * Copyright (C) 2013 Red Hat Inc.
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

module StringSet = Set.Make (String)
module G = Guestfs

let rpm_db_perform g root =
  let pf = g#inspect_get_package_format root in
  if pf = "rpm" then (
    let paths = g#glob_expand "/var/lib/rpm/__db.*" in
    Array.iter (
      fun filename ->
        try g#rm filename with G.Error _ -> ()
    ) paths;
    []
  )
  else []

let rpm_db_op = {
  name = "rpm-db";
  enabled_by_default = true;
  heading = s_"Remove host-specific RPM database files";
  pod_description = Some (s_"\
Remove host-specific RPM database files and locks.  RPM will
recreate these files automatically if needed.");
  extra_args = [];
  perform_on_filesystems = Some rpm_db_perform;
  perform_on_devices = None;
}

let () = register_operation rpm_db_op
