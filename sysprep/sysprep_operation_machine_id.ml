(* virt-sysprep
 * Copyright (C) 2012 Fujitsu Limited.
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

let machine_id_perform ~verbose ~quiet g root side_effects =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let path = "/etc/machine-id" in
    (try g#rm path with G.Error _ -> ());
    (try
       g#touch path;
       side_effects#created_file ()
     with G.Error _ -> ());
  )

let op = {
  defaults with
    name = "machine-id";
    enabled_by_default = true;
    heading = s_"Remove the local machine ID";
    pod_description = Some (s_"\
The machine ID is usually generated from a random source during system
installation and stays constant for all subsequent boots.  Optionally,
for stateless systems it is generated during runtime at boot if it is
found to be empty.");
    perform_on_filesystems = Some machine_id_perform;
}

let () = register_operation op
