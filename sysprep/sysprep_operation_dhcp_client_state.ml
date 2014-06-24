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
open Common_gettext.Gettext

module G = Guestfs

let dhcp_client_state_perform ~verbose ~quiet g root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    List.iter (
      fun glob -> Array.iter g#rm_rf (g#glob_expand glob)
    ) [ "/var/lib/dhclient/*"; "/var/lib/dhcp/*" (* RHEL 3 *) ]
  )

let op = {
  defaults with
    name = "dhcp-client-state";
    enabled_by_default = true;
    heading = s_"Remove DHCP client leases";
    perform_on_filesystems = Some dhcp_client_state_perform;
}

let () = register_operation op
