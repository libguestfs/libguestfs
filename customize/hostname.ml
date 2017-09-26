(* virt-sysprep
 * Copyright (C) 2012-2017 Red Hat Inc.
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

open Std_utils
open Tools_utils

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

  | "linux", ("rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based"), v
    when v >= 7 ->
    update_etc_hostname g hostname;
    update_etc_machine_info g hostname;
    true

  | "linux", ("debian"|"ubuntu"), _ ->
    let old_hostname = read_etc_hostname g in
    update_etc_hostname g hostname;
    replace_host_in_etc_hosts g old_hostname hostname;
    true

  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based"), _ ->
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
        fun line -> not (String.is_prefix line (key ^ "="))
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

and read_etc_hostname g =
  let filename = "/etc/hostname" in
  if g#is_file filename then (
    let lines = Array.to_list (g#read_lines filename) in
    match lines with
    | hd :: _ -> Some hd
    | [] -> None
  ) else
    None

and aug_hosts_expr =
  (* Matches everything in /etc/hosts except the IP address and comments. *)
  "/files/etc/hosts/*[label() != '#comment']/*[label() != 'ipaddr']"

and replace_host_in_etc_hosts g oldhost newhost =
  if g#is_file "/etc/hosts" then (
    let oldshortname, olddomainname =
      match oldhost with
      | None -> None, None
      | Some oldhost ->
         let s, d = String.split "." oldhost in Some s, Some d in
    let newshortname, newdomainname = String.split "." newhost in

    g#aug_init "/" 0;
    let matches = Array.to_list (g#aug_match aug_hosts_expr) in

    List.iter (
      fun m ->
        let value = g#aug_get m in

        (* Replace either "oldhostname" or "oldhostname.olddomainname". *)
        if oldhost = Some value then
          g#aug_set m newhost

        else if oldshortname = Some value then
          g#aug_set m newshortname

        (* On Debian/Ubuntu we also may find "unassigned-hostname"
         * which has to be replaced with the short hostname.
         *)
        else if value = "unassigned-hostname" then
          g#aug_set m newshortname

        (* Or we may find "unassigned-hostname.unassigned-domain". *)
        else if value = "unassigned-hostname.unassigned-domain" &&
                  newdomainname <> "" then
          g#aug_set m newhost
    ) matches;

    g#aug_save ()
  )
