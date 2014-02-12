(* virt-sysprep
 * Copyright (C) 2012-2014 Red Hat Inc.
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

open Common_utils

open Printf

let rec set_hostname (g : Guestfs.guestfs) root hostname =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  let major_version = g#inspect_get_major_version root in

  match typ, distro, major_version with
  (* Fedora 18 (hence RHEL 7+) changed to using /etc/hostname
   * (RHBZ#881953, RHBZ#858696).  We may also need to modify
   * /etc/machine-info (RHBZ#890027).
   *)
  | "linux", "fedora", v when v >= 18 ->
    update_etc_hostname g hostname;
    update_etc_machine_info g hostname;
    true

  | "linux", ("rhel"|"centos"|"scientificlinux"|"redhat-based"), v
    when v >= 7 ->
    update_etc_hostname g hostname;
    update_etc_machine_info g hostname;
    true

  | "linux", ("debian"|"ubuntu"), _ ->
    update_etc_hostname g hostname;
    true

  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"redhat-based"), _ ->
    replace_line_in_file g "/etc/sysconfig/network" "HOSTNAME" hostname;
    true

  | "linux", ("opensuse"|"sles"|"suse-based"), _ ->
    g#write "/etc/HOSTNAME" hostname;
    true

  | _ ->
    false

(* Replace <key>=... entry in file.  The code assumes it's a small,
 * plain text file.
 *)
and replace_line_in_file g filename key value =
  let content =
    if g#is_file filename then (
      let lines = Array.to_list (g#read_lines filename) in
      let lines = List.filter (
        fun line -> not (string_prefix line (key ^ "="))
      ) lines in
      let lines = lines @ [sprintf "%s=%s" key value] in
      String.concat "\n" lines ^ "\n"
    ) else (
      sprintf "%s=%s\n" key value
    ) in
  g#write filename content

and update_etc_hostname g hostname =
  g#write "/etc/hostname" (hostname ^ "\n")

and update_etc_machine_info g hostname =
  replace_line_in_file g "/etc/machine-info" "PRETTY_HOSTNAME" hostname
