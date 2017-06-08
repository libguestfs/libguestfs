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

open Std_utils
open Common_utils
open Common_gettext.Gettext

open Sysprep_operation

module G = Guestfs

let cron_spool_perform (g : Guestfs.guestfs) root side_effects =
  let is_seq path =
    let basename =
      match last_part_of path '/' with
      | Some x -> x
      | None -> path in
    basename = ".SEQ" in
  let reset f =
    if g#is_file f then
      (* This should overwrite the file in-place, as it's a very
       * small buffer which will be handled using internal_write.
       * This way, existing attributes like SELinux labels are
       * preserved.
       *)
      g#write f "00000\n" in

  rm_rf_only_files g ~filter:is_seq "/var/spool/cron/";
  reset "/var/spool/cron/atjobs/.SEQ";
  Array.iter g#rm (g#glob_expand "/var/spool/atjobs/*");
  reset "/var/spool/atjobs/.SEQ";
  Array.iter g#rm (g#glob_expand "/var/spool/atspool/*");
  rm_rf_only_files g ~filter:is_seq "/var/spool/at/";
  reset "/var/spool/at/.SEQ"

let op = {
  defaults with
    name = "cron-spool";
    enabled_by_default = true;
    heading = s_"Remove user at-jobs and cron-jobs";
    perform_on_filesystems = Some cron_spool_perform;
}

let () = register_operation op
