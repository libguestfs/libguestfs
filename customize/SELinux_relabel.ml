(* virt-customize
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

open Common_gettext.Gettext
open Common_utils

open Printf

module G = Guestfs

let relabel (g : G.guestfs) =
  (* Is the guest using SELinux? *)
  if g#is_file ~followsymlinks:true "/usr/sbin/load_policy" &&
     g#is_file ~followsymlinks:true "/etc/selinux/config" then (
    (* Is setfiles / SELinux relabelling functionality available? *)
    if g#feature_available [| "selinuxrelabel" |] then (
      (* Use Augeas to parse /etc/selinux/config. *)
      g#aug_init "/" (16+32) (* AUG_SAVE_NOOP | AUG_NO_LOAD *);
      (* See: https://bugzilla.redhat.com/show_bug.cgi?id=975412#c0 *)
      ignore (g#aug_rm "/augeas/load/*[\"/etc/selinux/config/\" !~ regexp('^') + glob(incl) + regexp('/.*')]");
      g#aug_load ();
      debug_augeas_errors g;

      (* Get the SELinux policy name, eg. "targeted", "minimum". *)
      let policy = g#aug_get "/files/etc/selinux/config/SELINUXTYPE" in
      g#aug_close ();

      (* Get the spec file name. *)
      let specfile =
        sprintf "/etc/selinux/%s/contexts/files/file_contexts" policy in

      (* Relabel everything. *)
      g#selinux_relabel ~force:true specfile "/";

      (* If that worked, we don't need to autorelabel. *)
      g#rm_f "/.autorelabel"
    )
    else (
      (* SELinux guest, but not SELinux host.  Fallback to this. *)
      g#touch "/.autorelabel"
    )
  )
