(* virt-sysprep
 * Copyright (C) 2012 Fujitsu Limited.
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

let pacct_log_perform (g : Guestfs.guestfs) root side_effects =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based") ->
    let files = g#glob_expand "/var/account/pacct*" in
    Array.iter (
      fun file ->
        try g#rm file with G.Error _ -> ()
      ) files;
    (try
       g#touch "/var/account/pacct";
       side_effects#created_file ()
     with G.Error _ -> ())

  | "linux", ("debian"|"ubuntu"|"kalilinux") ->
    let files = g#glob_expand "/var/log/account/pacct*" in
    Array.iter (
      fun file ->
        try g#rm file with G.Error _ -> ()
      ) files;
    (try
       g#touch "/var/log/account/pacct";
       side_effects#created_file ()
     with G.Error _ -> ())

  | _ -> ()

let op = {
  defaults with
    name = "pacct-log";
    enabled_by_default = true;
    heading = s_"Remove the process accounting log files";
    pod_description = Some (s_"\
The system wide process accounting will store to the pacct
log files if the process accounting is on.");
    perform_on_filesystems = Some pacct_log_perform;
}

let () = register_operation op
