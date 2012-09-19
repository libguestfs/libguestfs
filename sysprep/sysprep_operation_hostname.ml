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

open Utils
open Sysprep_operation
open Sysprep_gettext.Gettext

module G = Guestfs

let hostname = ref "localhost.localdomain"

let hostname_perform g root =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"redhat-based") ->
    (* Fedora 18 anaconda can create guests without
     * /etc/sysconfig/network file.  If this happens then we may need
     * to create this file (RHBZ#858696).
     *)
    let filename = "/etc/sysconfig/network" in
    if g#is_file filename then (
      (* Replace HOSTNAME=... entry.  The code assumes it's a small,
       * plain text file.
       *)
      let lines = Array.to_list (g#read_lines filename) in
      let lines = List.filter (
        fun line -> not (string_prefix line "HOSTNAME=")
      ) lines in
      let file =
        String.concat "\n" lines ^
          sprintf "\nHOSTNAME=%s\n" !hostname in
      g#write filename file;
    ) else (
      let file = sprintf "HOSTNAME=%s\n" !hostname in
      g#write filename file;
    );
    [ `Created_files ]

  | "linux", ("debian"|"ubuntu") ->
    g#write "/etc/hostname" !hostname;
    [ `Created_files ]

  | _ -> []

let hostname_op = {
  name = "hostname";
  enabled_by_default = true;
  heading = s_"Change the hostname of the guest";
  pod_description = Some (s_"\
This operation changes the hostname of the guest to the value
given in the I<--hostname> parameter.

If the I<--hostname> parameter is not given, then the hostname is changed
to C<localhost.localdomain>.");
  extra_args = [
    ("--hostname", Arg.Set_string hostname, s_"hostname" ^ " " ^ s_"New hostname"),
    s_"\
Change the hostname.  If not given, defaults to C<localhost.localdomain>."
  ];
  perform = hostname_perform;
}

let () = register_operation hostname_op
