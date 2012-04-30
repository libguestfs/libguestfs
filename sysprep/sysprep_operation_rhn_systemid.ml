(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

let rhn_systemid_perform g root =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in

  match typ, distro with
  | "linux", "rhel" ->
    (try g#rm "/etc/sysconfig/rhn/systemid" with G.Error _ -> ());
    []
  | _ -> []

let rhn_systemid_op = {
  name = "rhn-systemid";
  enabled_by_default = true;
  heading = s_"Remove the RHN system ID";
  pod_description = None;
  extra_args = [];
  perform = rhn_systemid_perform;
}

let () = register_operation rhn_systemid_op
