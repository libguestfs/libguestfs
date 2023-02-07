(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Std_utils

external rpm_init : unit -> unit = "guestfs_int_daemon_rpm_init"
external rpm_start_iterator : unit -> unit = "guestfs_int_daemon_rpm_start_iterator"
external rpm_next_application : unit -> Structs.application2 = "guestfs_int_daemon_rpm_next_application"
external rpm_end_iterator : unit -> unit = "guestfs_int_daemon_rpm_end_iterator"

(* librpm is troublesome when run from the main process.  In
 * particular it holds open some glibc NSS files.  Therefore we fork
 * before doing the chroot and any librpm operations.
 *
 * We could also consider in future limiting the time taken to run the
 * subprocess since it's unclear that parsing RPM config files from
 * the guest in particular is safe.
 *)
let rec internal_list_rpm_applications () =
  let chroot = Chroot.create ~name:"librpm" () in
  let apps = Chroot.f chroot list_rpm_applications () in
  eprintf "librpm returned %d installed packages\n%!" (List.length apps);
  apps

and list_rpm_applications () =
  rpm_init ();
  rpm_start_iterator ();
  let ret = ref [] in
  let rec loop () =
    try
      let app = rpm_next_application () in
      List.push_front app ret;
      loop ()
    with Not_found -> ()
  in
  loop ();
  rpm_end_iterator ();
  List.sort
    (fun { Structs.app2_name = n1 } { Structs.app2_name = n2 } ->
      compare n1 n2)
    !ret
