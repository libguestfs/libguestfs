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

let files = ref []

let make_id_from_filename filename =
  let ret = String.copy filename in
  for i = 0 to String.length ret - 1 do
    let c = String.unsafe_get ret i in
    if not ((c >= 'a' && c <= 'z') ||
               (c >= 'A' && c <= 'Z') ||
               (c >= '0' && c <= '9')) then
      String.unsafe_set ret i '-'
  done;
  ret

let firstboot_perform g root =
  (* Read the files and add them using the {!Firstboot} module. *)
  List.iter (
    fun filename ->
      let content = read_whole_file filename in
      let basename = Filename.basename filename in
      let id = make_id_from_filename basename in
      Firstboot.add_firstboot_script g root id content
  ) !files;
  [ `Created_files ]

let firstboot_op = {
  name = "firstboot";

  (* enabled_by_default because we only do anything if the
   * --firstboot parameter is used.
   *)
  enabled_by_default = true;

  heading = s_"Add scripts to run once at next boot";
  pod_description = Some (s_"\
Supply one of more shell scripts (using the I<--firstboot> option).

These are run the first time the guest boots, and then are
deleted.  So these are useful for performing last minute
configuration that must run in the context of the guest
operating system, for example C<yum update>.

Output or errors from the scripts are written to
C<~root/virt-sysprep-firstboot.log> (in the guest).

Currently this is only implemented for Linux guests using
either System V init, or systemd.");

  extra_args = [
    ("--firstboot", Arg.String (fun s -> files := s :: !files),
     s_"script" ^ " " ^ s_"run script once next time guest boots"),
    s_"\
Run script(s) once next time the guest boots.  You can supply
the I<--firstboot> option as many times as needed."
  ];

  perform_on_filesystems = Some firstboot_perform;
  perform_on_devices = None;
}

let () = register_operation firstboot_op
