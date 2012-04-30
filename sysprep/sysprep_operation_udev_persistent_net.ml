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

let udev_persistent_net_perform g root =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    (try g#rm "/etc/udev/rules.d/70-persistent-net.rules"
     with G.Error _ -> ());
    []
  )
  else []

let udev_persistent_net_op = {
  name = "udev-persistent-net";
  enabled_by_default = true;
  heading = s_"Remove udev persistent net rules";
  pod_description = Some (s_"\
Remove udev persistent net rules which map the guest's existing MAC
address to a fixed ethernet device (eg. eth0).

After a guest is cloned, the MAC address usually changes.  Since the
old MAC address occupies the old name (eg. eth0), this means the fresh
MAC address is assigned to a new name (eg. eth1) and this is usually
undesirable.  Erasing the udev persistent net rules avoids this.");
  extra_args = [];
  perform = udev_persistent_net_perform;
}

let () = register_operation udev_persistent_net_op
