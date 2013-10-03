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

open Printf

open Common_utils
open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let hostname = ref "localhost.localdomain"

let hostname_perform (g : Guestfs.guestfs) root =
  if Hostname.set_hostname g root !hostname then [ `Created_files ] else []

let op = {
  defaults with
    name = "hostname";
    enabled_by_default = true;
    heading = s_"Change the hostname of the guest";

    pod_description = Some (s_"\
This operation changes the hostname of the guest to the value
given in the I<--hostname> parameter.

If the I<--hostname> parameter is not given, then the hostname is changed
to C<localhost.localdomain>.");

    pod_notes = Some (s_"\
Currently this can only set the hostname on Linux guests.");

    extra_args = [
      ("--hostname", Arg.Set_string hostname, s_"hostname" ^ " " ^ s_"New hostname"),
      s_"\
Change the hostname.  If not given, defaults to C<localhost.localdomain>."
    ];

    perform_on_filesystems = Some hostname_perform;
}

let () = register_operation op
