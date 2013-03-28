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
open Common_gettext.Gettext

module G = Guestfs

let cron_spool_perform g root =
  Array.iter g#rm_rf (g#glob_expand "/var/spool/cron/*");
  Array.iter g#rm (g#glob_expand "/var/spool/atjobs/*");
  Array.iter g#rm (g#glob_expand "/var/spool/atjobs/.SEQ");
  Array.iter g#rm (g#glob_expand "/var/spool/atspool/*");
  Array.iter
    (fun path -> if not (g#is_dir path) then g#rm path)
    (g#glob_expand "/var/spool/at/*");
  Array.iter g#rm (g#glob_expand "/var/spool/at/.SEQ");
  Array.iter g#rm (g#glob_expand "/var/spool/at/spool/*");
  []

let cron_spool_op = {
  name = "cron-spool";
  enabled_by_default = true;
  heading = s_"Remove user at-jobs and cron-jobs";
  pod_description = None;
  extra_args = [];
  perform_on_filesystems = Some cron_spool_perform;
  perform_on_devices = None;
}

let () = register_operation cron_spool_op
