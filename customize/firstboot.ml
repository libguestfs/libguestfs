(* virt-customize
 * Copyright (C) 2012-2017 Red Hat Inc.
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

open Std_utils
open Common_utils
open Common_gettext.Gettext

open Regedit

let unix2dos s =
  String.concat "\r\n" (String.nsplit "\n" s)

let sanitize_name =
  let rex = PCRE.compile ~caseless:true "[^a-z0-9_]" in
  fun n ->
    let n = PCRE.replace ~global:true rex "-" n in
    let len = String.length n and max = 60 in
    if len >= max then String.sub n 0 max else n

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

  let systemd_target = "multi-user.target"

  let firstboot_service = sprintf "\
[Unit]
Description=libguestfs firstboot service
After=network.target
Before=prefdm.service

[Service]
Type=oneshot
ExecStart=%s/firstboot.sh start
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=inherit

[Install]
WantedBy=%s
" firstboot_dir systemd_target

  let rec install_service (g : Guestfs.guestfs) root distro major =
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
      install_sysvinit_service g root distro major

  (* Install the systemd firstboot service, if not installed already. *)
  and install_systemd_service g =
    (* RHBZ#1250955: systemd will only recognize unit files located
     * in /usr/lib/systemd/system/
     *)
    let unitdir = "/usr/lib/systemd/system" in
    g#mkdir_p unitdir;
    let unitfile = sprintf "%s/guestfs-firstboot.service" unitdir in
    g#write unitfile firstboot_service;
    g#mkdir_p (sprintf "/etc/systemd/system/%s.wants"
                       systemd_target);
    g#ln_sf unitfile (sprintf "/etc/systemd/system/%s.wants"
                              systemd_target);

    (* Try to remove the old firstboot.service files. *)
    let oldunitfile = sprintf "%s/firstboot.service" unitdir in
    if g#is_file oldunitfile then (
      g#rm_f "/etc/systemd/system/default.target.wants/firstboot.service";
      (* Remove the old firstboot.service only if it is one of our
       * versions. *)
      match g#checksum "md5" oldunitfile with
      | "6923781f7a1851b40b32b4960eb9a0fc"  (* < 1.23.24 *)
      | "56fafd8c990fc9d24e5b8497f3582e8d"  (* < 1.23.32 *)
      | "a83767e01cf398e2fd7c8f59d65d320a"  (* < 1.25.2 *)
      | "39aeb10df29104797e3a9aca4db37a6e" ->
        g#rm oldunitfile
      | csum ->
        warning (f_"firstboot: unknown version for old firstboot.service file %s (md5=%s), it will not be removed")
          oldunitfile csum
    );
    (* And the old default.target.wants/guestfs-firstboot.service from
     * libguestfs <= 1.37.17.
     *)
    g#rm_f "/etc/systemd/system/default.target.wants/guestfs-firstboot.service"

  and install_sysvinit_service g root distro major =
    match distro with
    | "fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based" ->
      install_sysvinit_redhat g
    | "opensuse"|"sles"|"suse-based" ->
      install_sysvinit_suse g
    | "debian" ->
      install_sysvinit_debian g;
      if major <= 7 then try_update_rc_d g root
    | "ubuntu" ->
      install_sysvinit_debian g
    | distro ->
      error (f_"guest type %s is not supported") distro

  and install_sysvinit_redhat g =
    g#mkdir_p "/etc/rc.d/rc2.d";
    g#mkdir_p "/etc/rc.d/rc3.d";
    g#mkdir_p "/etc/rc.d/rc5.d";
    g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
      "/etc/rc.d/rc2.d/S99guestfs-firstboot";
    g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
      "/etc/rc.d/rc3.d/S99guestfs-firstboot";
    g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
      "/etc/rc.d/rc5.d/S99guestfs-firstboot";

    (* Try to remove the files of the old service. *)
    g#rm_f "/etc/rc.d/rc2.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/rc.d/rc3.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/rc.d/rc5.d/S99virt-sysprep-firstboot"

  (* Make firstboot.sh look like a runlevel script to avoid insserv warnings. *)
  and install_sysvinit_suse g =
    g#mkdir_p "/etc/init.d/rc2.d";
    g#mkdir_p "/etc/init.d/rc3.d";
    g#mkdir_p "/etc/init.d/rc5.d";
    g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
      "/etc/init.d/guestfs-firstboot";
    g#ln_sf "../guestfs-firstboot"
      "/etc/init.d/rc2.d/S99guestfs-firstboot";
    g#ln_sf "../guestfs-firstboot"
      "/etc/init.d/rc3.d/S99guestfs-firstboot";
    g#ln_sf "../guestfs-firstboot"
      "/etc/init.d/rc5.d/S99guestfs-firstboot";

    (* Try to remove the files of the old service. *)
    g#rm_f "/etc/init.d/virt-sysprep-firstboot";
    g#rm_f "/etc/init.d/rc2.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/init.d/rc3.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/init.d/rc5.d/S99virt-sysprep-firstboot"

  and install_sysvinit_debian g =
    g#mkdir_p "/etc/init.d";
    g#mkdir_p "/etc/rc2.d";
    g#mkdir_p "/etc/rc3.d";
    g#mkdir_p "/etc/rc5.d";
    g#ln_sf (sprintf "%s/firstboot.sh" firstboot_dir)
      "/etc/init.d/guestfs-firstboot";
    g#ln_sf "../init.d/guestfs-firstboot"
      "/etc/rc2.d/S99guestfs-firstboot";
    g#ln_sf "../init.d/guestfs-firstboot"
      "/etc/rc3.d/S99guestfs-firstboot";
    g#ln_sf "../init.d/guestfs-firstboot"
      "/etc/rc5.d/S99guestfs-firstboot";

    (* Try to remove the files of the old service. *)
    g#rm_f "/etc/init.d/virt-sysprep-firstboot";
    g#rm_f "/etc/rc2.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/rc3.d/S99virt-sysprep-firstboot";
    g#rm_f "/etc/rc5.d/S99virt-sysprep-firstboot"

  (* On Debian 6 & 7 you have to run: update-rc.d guestfs-firstboot defaults
   * RHBZ#1019388.
   *)
  and try_update_rc_d g root =
    let guest_arch = g#inspect_get_arch root in
    let guest_arch_compatible = guest_arch_compatible guest_arch in
    let cmd = "update-rc.d guestfs-firstboot defaults" in
    if guest_arch_compatible then
      try ignore (g#sh cmd)
      with Guestfs.Error msg ->
        warning (f_"could not finish firstboot installation by running ‘%s’ because the command failed: %s")
                cmd msg
    else (
      warning (f_"cannot finish firstboot installation by running ‘%s’ because host cpu (%s) and guest arch (%s) are not compatible.  The firstboot service may not run at boot.")
              cmd Guestfs_config.host_cpu guest_arch
    )
end

module Windows = struct
  let rec install_service (g : Guestfs.guestfs) root =
    (* Either rhsrvany.exe or pvvxsvc.exe must exist.
     *
     * (Check also that it's not a dangling symlink but a real file).
     *)
    let services = ["rhsrvany.exe"; "pvvxsvc.exe"] in
    let srvany =
      try
        List.find (
          fun service -> Sys.file_exists (virt_tools_data_dir () // service)
        ) services
      with Not_found ->
       error (f_"One of rhsrvany.exe or pvvxsvc.exe is missing in %s.  One of them is required in order to install Windows firstboot scripts.  You can get one by building rhsrvany (https://github.com/rwmjones/rhsrvany)")
             (virt_tools_data_dir ()) in

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
      loop "" "C:" ["Program Files"; "Guestfs"; "Firstboot"] in

    g#mkdir_p (firstboot_dir // "scripts");

    (* Copy pvvxsvc or rhsrvany to the guest. *)
    g#upload (virt_tools_data_dir () // srvany) (firstboot_dir // srvany);

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

call :main >> \"%%log%%\" 2>&1
exit /b

:main
echo starting firstboot service

if not exist \"%%scripts_done%%\" (
  mkdir \"%%scripts_done%%\"
)

for %%%%f in (\"%%scripts%%\"\\*.bat) do (
  echo running \"%%%%f\"
  move \"%%%%f\" \"%%scripts_done%%\"
  pushd \"%%scripts_done%%\"
  call \"%%%%~nf\"
  set elvl=!errorlevel!
  echo .... exit code !elvl!
  popd
)

echo uninstalling firstboot service
%s -s firstboot uninstall
" firstboot_dir_win srvany in

    g#write (firstboot_dir // "firstboot.bat") (unix2dos firstboot_script);

    (* Open the SYSTEM hive. *)
    Registry.with_hive_write g (g#inspect_get_windows_system_hive root)
      (fun reg ->
        let current_cs = g#inspect_get_windows_current_control_set root in

        (* Add a new rhsrvany service to the system registry to execute
         * firstboot.  NB: All these edits are in the HKLM\SYSTEM hive.
         * No other hive may be modified here.
         *)
        let regedits = [
          [ current_cs; "services"; "firstboot" ],
          [ "Type", REG_DWORD 0x10_l;
            "Start", REG_DWORD 0x2_l;
            "ErrorControl", REG_DWORD 0x1_l;
            "ImagePath",
            REG_SZ (sprintf "%s\\%s -s firstboot" firstboot_dir_win srvany);
            "DisplayName", REG_SZ "Virt tools firstboot service";
            "ObjectName", REG_SZ "LocalSystem" ];

          [ current_cs; "services"; "firstboot"; "Parameters" ],
          [ "CommandLine",
            REG_SZ ("cmd /c \"" ^ firstboot_dir_win ^ "\\firstboot.bat\"");
            "PWD", REG_SZ firstboot_dir_win ];
        ] in
        reg_import reg regedits
      );

    firstboot_dir
end

let script_count = ref 0

let add_firstboot_script (g : Guestfs.guestfs) root name content =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  let major = g#inspect_get_major_version root in
  incr script_count;
  let filename = sprintf "%04d-%s" !script_count (sanitize_name name) in
  match typ, distro with
  | "linux", _ ->
    Linux.install_service g root distro major;
    let filename = Linux.firstboot_dir // "scripts" // filename in
    g#write filename content;
    g#chmod 0o755 filename

  | "windows", _ ->
    let firstboot_dir = Windows.install_service g root in
    let filename = firstboot_dir // "scripts" // filename ^ ".bat" in
    g#write filename (unix2dos content)

  | _ ->
    error (f_"guest type %s/%s is not supported") typ distro
