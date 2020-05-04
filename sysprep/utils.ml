(* virt-sysprep
 * Copyright (C) 2016 Red Hat Inc.
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

(* Utility functions. *)

open Printf

open Tools_utils
open Common_gettext.Gettext

let rec pod_of_list ?(style = `Dot) xs =
  match style with
  | `Verbatim -> String.concat "\n" (List.map ((^) " ") xs)
  | `Star -> _pod_of_list "*" xs
  | `Dash -> _pod_of_list "-" xs
  | `Dot -> _pod_of_list "·" xs

and _pod_of_list delim xs =
  "=over 4\n\n" ^
  String.concat "" (List.map (sprintf "=item %s\n\n%s\n\n" delim) xs) ^
  "=back"

let rec update_system_ca_store g root =
  let cmd = update_system_ca_store_command g root in
  match cmd with
  | None -> ()
  | Some cmd ->
    (* Try to run the command directly if possible, adding it as
     * firstboot script in case of incompatible architectures.
     *)
    let cmd = String.concat " " cmd in
    let incompatible_fn () =
      Firstboot.add_firstboot_script g root cmd cmd
    in

    run_in_guest_command g root ~incompatible_fn cmd

and update_system_ca_store_command g root =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based") ->
    Some [ "update-ca-trust"; "extract" ]

  | "linux", ("debian"|"ubuntu"|"kalilinux") ->
    Some [ "update-ca-certificates" ]

  | _, _ ->
    warning (f_"updating the system CA store on this guest %s/%s is not supported") typ distro;
    None
