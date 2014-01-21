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

open Random_seed

module G = Guestfs

let random_seed_perform (g : Guestfs.guestfs) root side_effects =
  if set_random_seed g root then
    side_effects#created_file ()

let op = {
  defaults with
    name = "random-seed";
    enabled_by_default = true;
    heading = s_"Generate random seed for guest";
    pod_description = Some (s_"\
Write some random bytes from the host into the random seed file of the
guest.

See L</RANDOM SEED> below.");
    perform_on_filesystems = Some random_seed_perform;
}

let () = register_operation op
