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

let files = ref []

let firstboot_perform g root =
  (* Read the files and add them using the {!Firstboot} module. *)
  let files = List.rev !files in
  let i = ref 0 in
  List.iter (
    fun filename ->
      incr i;
      let i = !i in
      let content = read_whole_file filename in
      Firstboot.add_firstboot_script g root i content
  ) files;
  if files <> [] then [ `Created_files ] else []

let op = {
  defaults with
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
C<~root/virt-sysprep-firstboot.log> (in the guest).");

    pod_notes = Some (s_"\
Currently this is only implemented for Linux guests using
either SysVinit-style scripts, Upstart or systemd.");

    extra_args = [
      { extra_argspec = "--firstboot", Arg.String (fun s -> files := s :: !files), s_"script" ^ " " ^ s_"run script once next time guest boots";
        extra_pod_argval = Some "SCRIPT";
        extra_pod_description = s_"\
Run script(s) once next time the guest boots.  You can supply
the I<--firstboot> option as many times as needed."
      }
    ];

    perform_on_filesystems = Some firstboot_perform;
}

let () = register_operation op
