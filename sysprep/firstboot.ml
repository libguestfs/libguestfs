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

(* For Linux guests. *)
let firstboot_dir = "/usr/lib/virt-sysprep"

let firstboot_sh = sprintf "\
#!/bin/sh -

d=%s/scripts
logfile=~root/virt-sysprep-firstboot.log

for f in $d/* ; do
  echo '=== Running' $f '===' >>$logfile
  $f >>$logfile 2>&1
  rm $f
done
" firstboot_dir

let firstboot_service = sprintf "\
[Unit]
Description=virt-sysprep firstboot service
After=syslog.target network.target
Before=prefdm.service

[Service]
Type=oneshot
ExecStart=%s/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
" firstboot_dir

let failed fs =
  ksprintf (fun msg -> failwith (s_"firstboot: failed: " ^ msg)) fs

let rec install_service g root =
  g#mkdir_p firstboot_dir;
  g#mkdir_p (sprintf "%s/scripts" firstboot_dir);
  g#write (sprintf "%s/firstboot.sh" firstboot_dir) firstboot_sh;
  g#chmod 0o755 (sprintf "%s/firstboot.sh" firstboot_dir);

  (* systemd, else assume sysvinit *)
  if g#is_dir "/etc/systemd" then
    install_systemd_service g root
  else
    install_sysvinit_service g root

(* Install the systemd firstboot service, if not installed already. *)
and install_systemd_service g root =
  g#write (sprintf "%s/firstboot.service" firstboot_dir) firstboot_service;
  g#mkdir_p "/etc/systemd/system/default.target.wants";
  g#ln_sf (sprintf "%s/firstboot.service" firstboot_dir)
    "/etc/systemd/system/default.target.wants"

and install_sysvinit_service g root =
  g#mkdir_p "/etc/rc.d/rc2.d";
  g#mkdir_p "/etc/rc.d/rc3.d";
  g#mkdir_p "/etc/rc.d/rc5.d";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc2.d/99virt-sysprep-firstboot";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc3.d/99virt-sysprep-firstboot";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc5.d/99virt-sysprep-firstboot"

let add_firstboot_script g root id content =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", _ ->
    install_service g root;
    let t = Int64.of_float (Unix.time ()) in
    let r = string_random8 () in
    let filename = sprintf "%s/scripts/%Ld-%s-%s" firstboot_dir t r id in
    g#write filename content;
    g#chmod 0o755 filename

  | _ ->
    failed "guest type %s/%s is not supported" typ distro
