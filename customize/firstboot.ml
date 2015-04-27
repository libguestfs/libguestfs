(* virt-customize
 * Copyright (C) 2012-2014 Red Hat Inc.
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

open Customize_utils
open Regedit

let unix2dos s =
  String.concat "\r\n" (Str.split_delim (Str.regexp_string "\n") s)

let sanitize_name =
  let rex = Str.regexp "[^A-Za-z0-9_]" in
  fun n ->
    Str.global_replace rex "-" n

(* For Linux guests. *)
module Linux = struct
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
d_done=%s/scripts-done
logfile=~root/virt-sysprep-firstboot.log

echo \"$0\" \"$@\" 2>&1 | tee -a $logfile
echo \"Scripts dir: $d\" 2>&1 | tee -a $logfile

if test \"$1\" = \"start\"
then
  mkdir -p $d_done
  for f in $d/* ; do
    if test -x \"$f\"
    then
      # move the script to the 'scripts-done' directory, so it is not
      # executed again at the next boot
      mv $f $d_done
      echo '=== Running' $f '===' 2>&1 | tee -a $logfile
      $d_done/$(basename $f) 2>&1 | tee -a $logfile
    fi
  done
  rm -f $d_done/*
fi
" firstboot_dir firstboot_dir

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
      error (f_"guest type %s is not supported") distro

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
end

module Windows = struct

  let rec install_service (g : Guestfs.guestfs) root =
    (* Get the data directory. *)
    let virt_tools_data_dir =
      try Sys.getenv "VIRT_TOOLS_DATA_DIR"
      with Not_found -> Config.datadir // "virt-tools" in

    (* rhsrvany.exe must exist.
     *
     * (Check also that it's not a dangling symlink but a real file).
     *)
    let rhsrvany_exe = virt_tools_data_dir // "rhsrvany.exe" in
    (try
       let chan = open_in rhsrvany_exe in
       close_in chan
     with
       Sys_error msg ->
         error (f_"'%s' is missing.  This file is required in order to install Windows firstboot scripts.  You can get it by building rhsrvany (https://github.com/rwmjones/rhsrvany).  Original error: %s")
           rhsrvany_exe msg
    );

    (* Create a directory for firstboot files in the guest. *)
    let firstboot_dir, firstboot_dir_win =
      let rec loop firstboot_dir firstboot_dir_win = function
        | [] -> firstboot_dir, firstboot_dir_win
        | dir :: path ->
          let firstboot_dir =
            if firstboot_dir = "" then "/" ^ dir else firstboot_dir // dir in
          let firstboot_dir_win = firstboot_dir_win ^ "\\" ^ dir in
          let firstboot_dir = g#case_sensitive_path firstboot_dir in
          g#mkdir_p firstboot_dir;
          loop firstboot_dir firstboot_dir_win path
      in
      loop "" "C:" ["Program Files"; "Red Hat"; "Firstboot"] in

    g#mkdir_p (firstboot_dir // "scripts");

    (* Copy rhsrvany to the guest. *)
    g#upload rhsrvany_exe (firstboot_dir // "rhsrvany.exe");

    (* Write a firstboot.bat control script which just runs the other
     * scripts in the directory.  Note we need to use CRLF line endings
     * in this script.
     *)
    let firstboot_script = sprintf "\
@echo off

setlocal EnableDelayedExpansion
set firstboot=%s
set log=%%firstboot%%\\log.txt

set scripts=%%firstboot%%\\scripts
set scripts_done=%%firstboot%%\\scripts-done

call :main > \"%%log%%\" 2>&1
exit /b

:main
echo starting firstboot service

if not exist \"%%scripts_done%%\" (
  mkdir \"%%scripts_done%%\"
)

for %%%%f in (\"%%scripts%%\"\\*.bat) do (
  echo running \"%%%%f\"
  call \"%%%%f\"
  set elvl=!errorlevel!
  echo .... exit code !elvl!
  if !elvl! equ 0 (
    move \"%%%%f\" \"%%scripts_done%%\"
  )
)

echo uninstalling firstboot service
rhsrvany.exe -s firstboot uninstall
" firstboot_dir_win in

    g#write (firstboot_dir // "firstboot.bat") (unix2dos firstboot_script);

    (* Open the SYSTEM hive. *)
    let systemroot = g#inspect_get_windows_systemroot root in
    let filename = sprintf "%s/system32/config/SYSTEM" systemroot in
    let filename = g#case_sensitive_path filename in
    g#hivex_open ~write:true filename;

    let root_node = g#hivex_root () in

    (* Find the 'Current' ControlSet. *)
    let current_cs =
      let select = g#hivex_node_get_child root_node "Select" in
      let valueh = g#hivex_node_get_value select "Current" in
      let value = int_of_le32 (g#hivex_value_value valueh) in
      sprintf "ControlSet%03Ld" value in

    (* Add a new rhsrvany service to the system registry to execute firstboot.
     * NB: All these edits are in the HKLM\SYSTEM hive.  No other
     * hive may be modified here.
     *)
    let regedits = [
      [ current_cs; "services"; "firstboot" ],
      [ "Type", REG_DWORD 0x10_l;
        "Start", REG_DWORD 0x2_l;
        "ErrorControl", REG_DWORD 0x1_l;
        "ImagePath",
          REG_SZ (firstboot_dir_win ^ "\\rhsrvany.exe -s firstboot");
        "DisplayName", REG_SZ "Virt tools firstboot service";
        "ObjectName", REG_SZ "LocalSystem" ];

      [ current_cs; "services"; "firstboot"; "Parameters" ],
      [ "CommandLine",
          REG_SZ ("cmd /c \"" ^ firstboot_dir_win ^ "\\firstboot.bat\"");
        "PWD", REG_SZ firstboot_dir_win ];
    ] in
    reg_import g root_node regedits;

    g#hivex_commit None;
    g#hivex_close ();

    firstboot_dir

end

let script_count = ref 0

let add_firstboot_script (g : Guestfs.guestfs) root name content =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  incr script_count;
  let filename = sprintf "%04d-%s" !script_count (sanitize_name name) in
  match typ, distro with
  | "linux", _ ->
    Linux.install_service g distro;
    let filename = Linux.firstboot_dir // "scripts" // filename in
    g#write filename content;
    g#chmod 0o755 filename

  | "windows", _ ->
    let firstboot_dir = Windows.install_service g root in
    let filename = firstboot_dir // "scripts" // filename ^ ".bat" in
    g#write filename (unix2dos content)

  | _ ->
    error (f_"guest type %s/%s is not supported") typ distro
