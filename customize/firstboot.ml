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
open Common_gettext.Gettext

(* For Linux guests. *)
let firstboot_dir = "/usr/lib/virt-sysprep"

let firstboot_sh = sprintf "\
#!/bin/sh -

### BEGIN INIT INFO
# Provides:          virt-sysprep
# Required-Start:    $null
# Should-Start:      $all
# Required-Stop:     $null
# Should-Stop:       $all
# Default-Start:     2 3 5
# Default-Stop:      0 1 6
# Short-Description: Start scripts to run once at next boot
# Description:       Start scripts to run once at next boot
#	These scripts run the first time the guest boots,
#	and then are deleted. Output or errors from the scripts
#	are written to ~root/virt-sysprep-firstboot.log.
### END INIT INFO

d=%s/scripts
logfile=~root/virt-sysprep-firstboot.log

echo \"$0\" \"$@\" 2>&1 | tee $logfile
echo \"Scripts dir: $d\" 2>&1 | tee $logfile

if test \"$1\" = \"start\"
then
  for f in $d/* ; do
    if test -x \"$f\"
    then
      echo '=== Running' $f '===' 2>&1 | tee $logfile
      $f 2>&1 | tee $logfile
      rm -f $f
    fi
  done
fi
" firstboot_dir

let firstboot_service = sprintf "\
[Unit]
Description=virt-sysprep firstboot service
After=network.target
Before=prefdm.service

[Service]
Type=oneshot
ExecStart=%s/firstboot.sh start
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=inherit

[Install]
WantedBy=default.target
" firstboot_dir

let failed fs =
  ksprintf (fun msg -> failwith (s_"firstboot: failed: " ^ msg)) fs

let rec install_service (g : Guestfs.guestfs) distro =
  g#mkdir_p firstboot_dir;
  g#mkdir_p (sprintf "%s/scripts" firstboot_dir);
  g#write (sprintf "%s/firstboot.sh" firstboot_dir) firstboot_sh;
  g#chmod 0o755 (sprintf "%s/firstboot.sh" firstboot_dir);

  (* Note we install both systemd and sysvinit services.  This is
   * because init systems can be switched at runtime, and it's easy to
   * tell if systemd is installed (eg. Ubuntu uses upstart but installs
   * systemd configuration directories).  There is no danger of a
   * firstboot script running twice because they disable themselves
   * after running.
   *)
  if g#is_dir "/etc/systemd/system" then
    install_systemd_service g;
  if g#is_dir "/etc/rc.d" || g#is_dir "/etc/init.d" then
    install_sysvinit_service g distro

(* Install the systemd firstboot service, if not installed already. *)
and install_systemd_service g =
  g#write (sprintf "%s/firstboot.service" firstboot_dir) firstboot_service;
  g#mkdir_p "/etc/systemd/system/default.target.wants";
  g#ln_sf (sprintf "%s/firstboot.service" firstboot_dir)
    "/etc/systemd/system/default.target.wants"

and install_sysvinit_service g = function
  | "fedora"|"rhel"|"centos"|"scientificlinux"|"redhat-based" ->
    install_sysvinit_redhat g
  | "opensuse"|"sles"|"suse-based" ->
    install_sysvinit_suse g
  | "debian"|"ubuntu" ->
    install_sysvinit_debian g
  | distro ->
    failed "guest type %s is not supported" distro

and install_sysvinit_redhat g =
  g#mkdir_p "/etc/rc.d/rc2.d";
  g#mkdir_p "/etc/rc.d/rc3.d";
  g#mkdir_p "/etc/rc.d/rc5.d";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc2.d/S99virt-sysprep-firstboot";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc3.d/S99virt-sysprep-firstboot";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/rc.d/rc5.d/S99virt-sysprep-firstboot"

(* Make firstboot.sh look like a runlevel script to avoid insserv warnings. *)
and install_sysvinit_suse g =
  g#mkdir_p "/etc/init.d/rc2.d";
  g#mkdir_p "/etc/init.d/rc3.d";
  g#mkdir_p "/etc/init.d/rc5.d";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/init.d/virt-sysprep-firstboot";
  g#ln_sf "../virt-sysprep-firstboot"
    "/etc/init.d/rc2.d/S99virt-sysprep-firstboot";
  g#ln_sf "../virt-sysprep-firstboot"
    "/etc/init.d/rc3.d/S99virt-sysprep-firstboot";
  g#ln_sf "../virt-sysprep-firstboot"
    "/etc/init.d/rc5.d/S99virt-sysprep-firstboot"

and install_sysvinit_debian g =
  g#mkdir_p "/etc/init.d";
  g#mkdir_p "/etc/rc2.d";
  g#mkdir_p "/etc/rc3.d";
  g#mkdir_p "/etc/rc5.d";
  g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
    "/etc/init.d/virt-sysprep-firstboot";
  g#ln_sf "/etc/init.d/virt-sysprep-firstboot"
    "/etc/rc2.d/S99virt-sysprep-firstboot";
  g#ln_sf "/etc/init.d/virt-sysprep-firstboot"
    "/etc/rc3.d/S99virt-sysprep-firstboot";
  g#ln_sf "/etc/init.d/virt-sysprep-firstboot"
    "/etc/rc5.d/S99virt-sysprep-firstboot"

let add_firstboot_script (g : Guestfs.guestfs) root i content =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", _ ->
    install_service g distro;
    let t = Int64.of_float (Unix.time ()) in
    let r = string_random8 () in
    let filename = sprintf "%s/scripts/%04d-%Ld-%s" firstboot_dir i t r in
    g#write filename content;
    g#chmod 0o755 filename

  | _ ->
    failed "guest type %s/%s is not supported" typ distro
