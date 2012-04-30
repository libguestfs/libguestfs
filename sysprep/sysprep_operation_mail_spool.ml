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
open Sysprep_gettext.Gettext

module G = Guestfs

let mail_spool_perform g root =
  List.iter (
    fun glob -> Array.iter g#rm_rf (g#glob_expand glob)
  ) [
    "/var/spool/mail/*";
    "/var/mail/*";
  ];
  []

let mail_spool_op = {
  name = "mail-spool";
  enabled_by_default = true;
  heading = s_"Remove email from the local mail spool directory";
  pod_description = None;
  extra_args = [];
  perform = mail_spool_perform;
}

let () = register_operation mail_spool_op
