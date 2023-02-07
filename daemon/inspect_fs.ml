(* guestfs-inspection
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Mountable
open Inspect_types
open Inspect_utils

let rec check_for_filesystem_on mountable vfs_type =
  if verbose () then
    eprintf "check_for_filesystem_on: %s (%s)\n%!"
            (Mountable.to_string mountable) vfs_type;

  let role =
    let is_swap = vfs_type = "swap" in
    if is_swap then
      Some RoleSwap
    else (
      (* Try mounting the device.  Ignore errors if we can't do this. *)
      let mounted =
        if vfs_type = "ufs" then ( (* Hack for the *BSDs. *)
          (* FreeBSD fs is a variant of ufs called ufs2 ... *)
          try
            Mount.mount_vfs "ro,ufstype=ufs2" "ufs" mountable "/";
            true
          with _ ->
            (* while NetBSD and OpenBSD use another variant labeled 44bsd *)
            try
              Mount.mount_vfs "ro,ufstype=44bsd" "ufs" mountable "/";
              true
            with _ -> false
        ) else (
          try Mount.mount_ro mountable "/";
              true
          with _ -> false
        ) in
      if not mounted then None
      else (
        let role = check_filesystem mountable in
        Mount_utils.umount_all ();
        role
      )
    ) in

  match role with
  | None -> None
  | Some role ->
     Some { fs_location = { mountable ; vfs_type }; role }

(* When this function is called, the filesystem is mounted on sysroot (). *)
and check_filesystem mountable =
  let role = ref `Other in
  (* The following struct is mutated in place by callees.  However we
   * need to make a copy of the object here so we don't mutate the
   * null_inspection_data struct!
   *)
  let data = null_inspection_data () in

  let debug_matching what =
    if verbose () then
      eprintf "check_filesystem: %s matched %s\n%!"
              (Mountable.to_string mountable) what
  in

  (* Grub /boot? *)
  if Is.is_file "/grub/menu.lst" ||
     Is.is_file "/grub/grub.conf" ||
     Is.is_file "/grub2/grub.cfg" then (
    debug_matching "Grub /boot";
    ()
  )
  (* FreeBSD root? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/bin" &&
          Is.is_file "/etc/freebsd-update.conf" &&
          Is.is_file "/etc/fstab" then (
    debug_matching "FreeBSD root";
    role := `Root;
    Inspect_fs_unix.check_freebsd_root mountable data
  )
  (* NetBSD root? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/bin" &&
          Is.is_file "/netbsd" &&
          Is.is_file "/etc/fstab" &&
          Is.is_file "/etc/release" then (
    debug_matching "NetBSD root";
    role := `Root;
    Inspect_fs_unix.check_netbsd_root mountable data;
  )
  (* OpenBSD root? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/bin" &&
          Is.is_file "/bsd" &&
          Is.is_file "/etc/fstab" &&
          Is.is_file "/etc/motd" then (
    debug_matching "OpenBSD root";
    role := `Root;
    Inspect_fs_unix.check_openbsd_root mountable data;
  )
  (* Hurd root? *)
  else if Is.is_file "/hurd/console" &&
          Is.is_file "/hurd/hello" &&
          Is.is_file "/hurd/null" then (
    debug_matching "Hurd root";
    role := `Root;
    Inspect_fs_unix.check_hurd_root mountable data;
  )
  (* Minix root? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/bin" &&
          Is.is_file "/service/vm" &&
          Is.is_file "/etc/fstab" &&
          Is.is_file "/etc/version" then (
    debug_matching "Minix root";
    role := `Root;
    Inspect_fs_unix.check_minix_root data;
  )
  (* Linux root? *)
  else if Is.is_dir "/etc" &&
          (Is.is_dir "/bin" ||
           is_symlink_to "/bin" "usr/bin") &&
          (Is.is_file "/etc/fstab" ||
           Is.is_file "/etc/hosts") then (
    debug_matching "Linux root";
    role := `Root;
    Inspect_fs_unix.check_linux_root mountable data;
  )
  (* CoreOS root? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/root" &&
          Is.is_dir "/home" &&
          Is.is_dir "/usr" &&
          Is.is_file "/etc/coreos/update.conf" then (
    debug_matching "CoreOS root";
    role := `Root;
    Inspect_fs_unix.check_coreos_root mountable data;
  )
  (* Linux /usr/local? *)
  else if Is.is_dir "/etc" &&
          Is.is_dir "/bin" &&
          Is.is_dir "/share" &&
          not (Is.is_dir "/local") &&
          not (Is.is_file "/etc/fstab") then (
    debug_matching "Linux /usr/local";
    ()
  )
  (* Linux /usr? *)
  else if Is.is_dir "/bin" &&
          Is.is_dir "/local" &&
          Is.is_dir "/share" &&
          Is.is_dir "/src" &&
          not (Is.is_file "/etc/fstab") then (
    debug_matching "Linux /usr";
    role := `Usr;
    Inspect_fs_unix.check_linux_usr data;
  )
  (* CoreOS /usr? *)
  else if Is.is_dir "/bin" &&
          Is.is_dir "/share" &&
          Is.is_dir "/local" &&
          Is.is_dir "/share/coreos" then (
    debug_matching "CoreOS /usr";
    role := `Usr;
    Inspect_fs_unix.check_coreos_usr mountable data;
  )
  (* Linux /var? *)
  else if Is.is_dir "/log" &&
          Is.is_dir "/run" &&
          Is.is_dir "/spool" then (
    debug_matching "Linux /var";
    ()
  )
  (* Windows root? *)
  else if Inspect_fs_windows.is_windows_systemroot () then (
    debug_matching "Windows root";
    role := `Root;
    Inspect_fs_windows.check_windows_root data;
  )
  (* Windows volume with installed applications (but not root)? *)
  else if is_dir_nocase "/System Volume Information" &&
          is_dir_nocase "/Program Files" then (
    debug_matching "Windows volume with installed applications";
    ()
  )
  (* Windows volume (but not root)? *)
  else if is_dir_nocase "/System Volume Information" then (
    debug_matching "Windows volume without installed applications";
    ()
  )
  (* FreeDOS? *)
  else if is_dir_nocase "/FDOS" &&
          is_file_nocase "/FDOS/FREEDOS.BSS" then (
    debug_matching "FreeDOS";
    role := `Root;
    data.os_type <- Some OS_TYPE_DOS;
    data.distro <- Some DISTRO_FREEDOS;
    (* FreeDOS is a mix of 16 and 32 bit, but
     * assume it requires a 32 bit i386 processor.
     *)
    data.arch <- Some "i386"
  )
  (* MS-DOS? *)
  else if is_dir_nocase "/DOS" &&
          is_file_nocase "/DOS/COMMAND.COM" then (
    debug_matching "MS-DOS";
    role := `Root;
    data.os_type <- Some OS_TYPE_DOS;
    data.distro <- Some DISTRO_MSDOS;
    (* MS-DOS is a mix of 16 and 32 bit, but
     * assume it requires a 32 bit i386 processor.
     *)
    data.arch <- Some "i386"
  )
  (* None of the above. *)
  else (
    debug_matching "no known OS partition"
  );

  (* The above code should have set [data.os_type] and [data.distro]
   * fields, so we can now guess the package management system.
   *)
  data.package_format <- check_package_format data;
  data.package_management <- check_package_management data;

  match !role with
  | `Root -> Some (RoleRoot data)
  | `Usr -> Some (RoleUsr data)
  | `Other -> Some RoleOther

and is_symlink_to file wanted_target =
  if not (Is.is_symlink file) then false
  else Link.readlink file = wanted_target

(* At the moment, package format and package management are just a
 * simple function of the [distro] and [version[0]] fields, so these
 * can never return an error.  We might be cleverer in future.
 *)
and check_package_format { distro } =
  match distro with
  | None -> None
  | Some DISTRO_ALTLINUX
  | Some DISTRO_CENTOS
  | Some DISTRO_ROCKY
  | Some DISTRO_FEDORA
  | Some DISTRO_MAGEIA
  | Some DISTRO_MANDRIVA
  | Some DISTRO_MEEGO
  | Some DISTRO_NEOKYLIN
  | Some DISTRO_OPENMANDRIVA
  | Some DISTRO_OPENSUSE
  | Some DISTRO_ORACLE_LINUX
  | Some DISTRO_REDHAT_BASED
  | Some DISTRO_RHEL
  | Some DISTRO_SCIENTIFIC_LINUX
  | Some DISTRO_SLES
  | Some DISTRO_SUSE_BASED ->
     Some PACKAGE_FORMAT_RPM
  | Some DISTRO_DEBIAN
  | Some DISTRO_KALI_LINUX
  | Some DISTRO_KYLIN (* supposedly another Ubuntu derivative *)
  | Some DISTRO_LINUX_MINT
  | Some DISTRO_UBUNTU ->
     Some PACKAGE_FORMAT_DEB
  | Some DISTRO_ARCHLINUX ->
     Some PACKAGE_FORMAT_PACMAN
  | Some DISTRO_GENTOO ->
     Some PACKAGE_FORMAT_EBUILD
  | Some DISTRO_PARDUS ->
     Some PACKAGE_FORMAT_PISI
  | Some DISTRO_ALPINE_LINUX ->
     Some PACKAGE_FORMAT_APK
  | Some DISTRO_VOID_LINUX ->
     Some PACKAGE_FORMAT_XBPS
  | Some DISTRO_BUILDROOT
  | Some DISTRO_CIRROS
  | Some DISTRO_COREOS
  | Some DISTRO_FREEBSD
  | Some DISTRO_FREEDOS
  | Some DISTRO_FRUGALWARE
  | Some DISTRO_MSDOS
  | Some DISTRO_NETBSD
  | Some DISTRO_OPENBSD
  | Some DISTRO_PLD_LINUX
  | Some DISTRO_SLACKWARE
  | Some DISTRO_TTYLINUX
  | Some DISTRO_WINDOWS ->
     None

and check_package_management { distro; version } =
  let major = match version with None -> 0 | Some (major, _) -> major in
  match distro with
  | None -> None

  | Some DISTRO_MEEGO ->
     Some PACKAGE_MANAGEMENT_YUM

  | Some DISTRO_FEDORA ->
    (* If Fedora >= 22 and dnf is installed, say "dnf". *)
     if major >= 22 && Is.is_file ~followsymlinks:true "/usr/bin/dnf" then
       Some PACKAGE_MANAGEMENT_DNF
     else if major >= 1 then
       Some PACKAGE_MANAGEMENT_YUM
     else
       (* Probably parsing the release file failed, see RHBZ#1332025. *)
       None

  | Some DISTRO_NEOKYLIN ->
     (* We don't have access to NeoKylin for testing, but it is
      * supposed to be a Fedora derivative.
      *)
     Some PACKAGE_MANAGEMENT_DNF

  | Some DISTRO_CENTOS
  | Some DISTRO_ROCKY
  | Some DISTRO_ORACLE_LINUX
  | Some DISTRO_REDHAT_BASED
  | Some DISTRO_RHEL
  | Some DISTRO_SCIENTIFIC_LINUX ->
     if major >= 8 then
       Some PACKAGE_MANAGEMENT_DNF
     else if major >= 5 then
       Some PACKAGE_MANAGEMENT_YUM
     else if major >= 2 then
       Some PACKAGE_MANAGEMENT_UP2DATE
     else
       (* Probably parsing the release file failed, see RHBZ#1332025. *)
       None

  | Some DISTRO_ALTLINUX
  | Some DISTRO_DEBIAN
  | Some DISTRO_KALI_LINUX
  | Some DISTRO_KYLIN (* supposedly another Ubuntu derivative *)
  | Some DISTRO_LINUX_MINT
  | Some DISTRO_UBUNTU ->
     Some PACKAGE_MANAGEMENT_APT

  | Some DISTRO_ARCHLINUX ->
     Some PACKAGE_MANAGEMENT_PACMAN

  | Some DISTRO_GENTOO ->
     Some PACKAGE_MANAGEMENT_PORTAGE

  | Some DISTRO_PARDUS ->
     Some PACKAGE_MANAGEMENT_PISI

  | Some DISTRO_MAGEIA
  | Some DISTRO_MANDRIVA ->
     Some PACKAGE_MANAGEMENT_URPMI

  | Some DISTRO_OPENSUSE
  | Some DISTRO_SLES
  | Some DISTRO_SUSE_BASED ->
     Some PACKAGE_MANAGEMENT_ZYPPER

  | Some DISTRO_ALPINE_LINUX ->
     Some PACKAGE_MANAGEMENT_APK

  | Some DISTRO_VOID_LINUX ->
     Some PACKAGE_MANAGEMENT_XBPS

  | Some DISTRO_OPENMANDRIVA ->
     Some PACKAGE_MANAGEMENT_DNF

  | Some DISTRO_BUILDROOT
  | Some DISTRO_CIRROS
  | Some DISTRO_COREOS
  | Some DISTRO_FREEBSD
  | Some DISTRO_FREEDOS
  | Some DISTRO_FRUGALWARE
  | Some DISTRO_MSDOS
  | Some DISTRO_NETBSD
  | Some DISTRO_OPENBSD
  | Some DISTRO_PLD_LINUX
  | Some DISTRO_SLACKWARE
  | Some DISTRO_TTYLINUX
  | Some DISTRO_WINDOWS ->
    None

