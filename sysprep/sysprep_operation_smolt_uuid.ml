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

let smolt_uuid_perform g root =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    let files = [ "/etc/sysconfig/hw-uuid";
                  "/etc/smolt/uuid";
                  "/etc/smolt/hw-uuid" ] in
    List.iter (
      fun file -> try g#rm file with G.Error _ -> ()
    ) files;

    []
  )
  else []

let smolt_uuid_op = {
  name = "smolt-uuid";
  enabled_by_default = true;
  heading = s_"Remove the Smolt hardware UUID";
  pod_description = None;
  extra_args = [];
  perform = smolt_uuid_perform;
}

let () = register_operation smolt_uuid_op
