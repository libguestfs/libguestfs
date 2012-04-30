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

let random_seed_perform g root =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    let files = [
      "/var/lib/random-seed"; (* Fedora *)
      "/var/lib/urandom/random-seed"; (* Debian *)
    ] in
    List.iter (
      fun file ->
        if g#is_file file then (
          (* Get 8 bytes of randomness from the host. *)
          let chan = open_in "/dev/urandom" in
          let buf = String.create 8 in
          really_input chan buf 0 8;
          close_in chan;

          g#write file buf
        )
    ) files;
    [ `Created_files ]
  )
  else []

let random_seed_op = {
  name = "random-seed";
  enabled_by_default = true;
  heading = s_"Generate random seed for guest";
  pod_description = Some (s_"\
Write some random bytes from the host into the random seed file of the
guest.

See L</RANDOM SEED> below.");
  extra_args = [];
  perform = random_seed_perform;
}

let () = register_operation random_seed_op
