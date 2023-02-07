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

open C_utils
open Std_utils

open Utils
open Inspect_types
open Inspect_utils

let re_fedora = PCRE.compile "Fedora release (\\d+)"
let re_rhel_old = PCRE.compile "Red Hat.*release (\\d+).*Update (\\d+)"
let re_rhel = PCRE.compile "Red Hat.*release (\\d+)\\.(\\d+)"
let re_rhel_no_minor = PCRE.compile "Red Hat.*release (\\d+)"
let re_centos_old = PCRE.compile "CentOS.*release (\\d+).*Update (\\d+)"
let re_centos = PCRE.compile "CentOS.*release (\\d+)\\.(\\d+)"
let re_centos_no_minor = PCRE.compile "CentOS.*release (\\d+)"
let re_rocky = PCRE.compile "Rocky Linux.*release (\\d+)\\.(\\d+)"
let re_rocky_no_minor = PCRE.compile "Rocky Linux.*release (\\d+)"
let re_scientific_linux_old =
  PCRE.compile "Scientific Linux.*release (\\d+).*Update (\\d+)"
let re_scientific_linux =
  PCRE.compile "Scientific Linux.*release (\\d+)\\.(\\d+)"
let re_scientific_linux_no_minor =
  PCRE.compile "Scientific Linux.*release (\\d+)"
let re_oracle_linux_old =
  PCRE.compile "Oracle Linux.*release (\\d+).*Update (\\d+)"
let re_oracle_linux =
  PCRE.compile "Oracle Linux.*release (\\d+)\\.(\\d+)"
let re_oracle_linux_no_minor = PCRE.compile "Oracle Linux.*release (\\d+)"
let re_netbsd = PCRE.compile "^NetBSD (\\d+)\\.(\\d+)"
let re_opensuse = PCRE.compile "^(openSUSE|SuSE Linux|SUSE LINUX) "
let re_sles = PCRE.compile "^SUSE (Linux|LINUX) Enterprise "
let re_nld = PCRE.compile "^Novell Linux Desktop "
let re_sles_version = PCRE.compile "^VERSION = (\\d+)"
let re_sles_patchlevel = PCRE.compile "^PATCHLEVEL = (\\d+)"
let re_minix = PCRE.compile "^(\\d+)\\.(\\d+)(\\.(\\d+))?"
let re_openbsd = PCRE.compile "^OpenBSD (\\d+|\\?)\\.(\\d+|\\?)"
let re_frugalware = PCRE.compile "Frugalware (\\d+)\\.(\\d+)"
let re_pldlinux = PCRE.compile "(\\d+)\\.(\\d+) PLD Linux"
let re_neokylin_version = PCRE.compile "^V(\\d+)Update(\\d+)$"
let re_openmandriva =
  PCRE.compile "OpenMandriva.*release (\\d+)\\.(\\d+)\\.?(\\d+)? .*"

let arch_binaries =
  [ "/bin/bash"; "/bin/ls"; "/bin/echo"; "/bin/rm"; "/bin/sh" ]

(* List of typical rolling distros, to ease handling them for common
 * features.
 *)
let rolling_distros =
  [ DISTRO_ARCHLINUX; DISTRO_GENTOO; DISTRO_VOID_LINUX ]

(* Parse a os-release file.
 *
 * Only few fields are parsed, falling back to the usual detection if we
 * cannot read all of them.
 *
 * For the format of os-release, see also:
 * http://www.freedesktop.org/software/systemd/man/os-release.html
 *)
let rec parse_os_release release_file data =
  let chroot = Chroot.create ~name:"parse_os_release" () in
  let lines = Chroot.f chroot read_small_file release_file in

  match lines with
  | None -> false
  | Some lines ->
     let values = parse_key_value_strings ~unquote:shell_unquote lines in
     List.iter (
       fun (key, value) ->
         if key = "ID" then (
           let distro = distro_of_os_release_id value in
           match distro with
           | Some _ as distro -> data.distro <- distro
           | None -> ()
         )
         else if key = "PRETTY_NAME" then
           data.product_name <- Some value
         else if key = "VERSION_ID" then
           parse_os_release_version_id value data
         else if key = "BUILD_ID" then
           data.build_id <- Some value
       ) values;

     (* If we haven't got all the fields, exit right away. *)
     if data.distro = None || data.product_name = None then
       false
     else (
       match data with
       (* os-release in Debian and CentOS does not provide the full
        * version number (VERSION_ID), just the major part of it.  If
        * we detect that situation then bail out and use the release
        * files instead.
        *)
       | { distro = Some (DISTRO_DEBIAN|DISTRO_CENTOS|DISTRO_ROCKY);
           version = Some (_, 0) } ->
          false

       (* Rolling distros: no VERSION_ID available. *)
       | { distro = Some d; version = None } when List.mem d rolling_distros ->
          data.version <- Some (0, 0);
          true

       (* No version detected, so fall back to other ways. *)
       | { version = None } ->
          false

       | _ -> true
     )

and parse_os_release_version_id value data =
  (* NeoKylin uses a non-standard format in the VERSION_ID
   * field (RHBZ#1476081).
   *)
  if PCRE.matches re_neokylin_version value then (
    let major = int_of_string (PCRE.sub 1)
    and minor = int_of_string (PCRE.sub 2) in
    data.version <- Some (major, minor)
  )
  else
    parse_version_from_major_minor value data

(* ID="fedora" => Some DISTRO_FEDORA *)
and distro_of_os_release_id = function
  | "alpine" -> Some DISTRO_ALPINE_LINUX
  | "altlinux" -> Some DISTRO_ALTLINUX
  | "arch" -> Some DISTRO_ARCHLINUX
  | "centos" -> Some DISTRO_CENTOS
  | "coreos" -> Some DISTRO_COREOS
  | "debian" -> Some DISTRO_DEBIAN
  | "fedora" -> Some DISTRO_FEDORA
  | "frugalware" -> Some DISTRO_FRUGALWARE
  | "gentoo" -> Some DISTRO_GENTOO
  | "kali" -> Some DISTRO_KALI_LINUX
  | "kylin" -> Some DISTRO_KYLIN
  | "mageia" -> Some DISTRO_MAGEIA
  | "neokylin" -> Some DISTRO_NEOKYLIN
  | "openmandriva" -> Some DISTRO_OPENMANDRIVA
  | "opensuse" -> Some DISTRO_OPENSUSE
  | s when String.is_prefix s "opensuse-" -> Some DISTRO_OPENSUSE
  | "pardus" -> Some DISTRO_PARDUS
  | "pld" -> Some DISTRO_PLD_LINUX
  | "rhel" -> Some DISTRO_RHEL
  | "rocky" -> Some DISTRO_ROCKY
  | "sles" | "sled" -> Some DISTRO_SLES
  | "ubuntu" -> Some DISTRO_UBUNTU
  | "void" -> Some DISTRO_VOID_LINUX
  | value ->
     eprintf "/etc/os-release: unknown ID=%s\n" value;
     None

(* Ubuntu has /etc/lsb-release containing:
 *   DISTRIB_ID=Ubuntu                                # Distro
 *   DISTRIB_RELEASE=10.04                            # Version
 *   DISTRIB_CODENAME=lucid
 *   DISTRIB_DESCRIPTION="Ubuntu 10.04.1 LTS"         # Product name
 *
 * [Ubuntu-derived ...] Linux Mint was found to have this:
 *   DISTRIB_ID=LinuxMint
 *   DISTRIB_RELEASE=10
 *   DISTRIB_CODENAME=julia
 *   DISTRIB_DESCRIPTION="Linux Mint 10 Julia"
 * Linux Mint also has /etc/linuxmint/info with more information,
 * but we can use the LSB file.
 *
 * Mandriva has:
 *   LSB_VERSION=lsb-4.0-amd64:lsb-4.0-noarch
 *   DISTRIB_ID=MandrivaLinux
 *   DISTRIB_RELEASE=2010.1
 *   DISTRIB_CODENAME=Henry_Farman
 *   DISTRIB_DESCRIPTION="Mandriva Linux 2010.1"
 * Mandriva also has a normal release file called /etc/mandriva-release.
 *
 * CoreOS has a /etc/lsb-release link to /usr/share/coreos/lsb-release containing:
 *   DISTRIB_ID=CoreOS
 *   DISTRIB_RELEASE=647.0.0
 *   DISTRIB_CODENAME="Red Dog"
 *   DISTRIB_DESCRIPTION="CoreOS 647.0.0"
 *)
and parse_lsb_release release_file data =
  let chroot = Chroot.create ~name:"parse_lsb_release" () in
  let lines = Chroot.f chroot read_small_file release_file in

  match lines with
  | None -> false
  | Some lines ->
     (* Some distros (eg. RHEL 3) have a bare lsb-release file that might
      * just contain the LSB_VERSION field and nothing else.  In that case
      * we must bail out (return false).
      *)
     let ok = ref false in

     let values = parse_key_value_strings ~unquote:simple_unquote lines in
     List.iter (
       fun (key, value) ->
         if verbose () then
           eprintf "parse_lsb_release: parsing: %s=%s\n%!" key value;

         if key = "DISTRIB_ID" then (
           let distro = distro_of_lsb_release_distrib_id value in
           match distro with
           | Some _ as distro ->
             ok := true;
             data.distro <- distro
           | None -> ()
         )
         else if key = "DISTRIB_RELEASE" then
           parse_version_from_major_minor value data
         else if key = "DISTRIB_DESCRIPTION" then (
           ok := true;
           data.product_name <- Some value
         )
     ) values;

     !ok

(* DISTRIB_ID="Ubuntu" => Some DISTRO_UBUNTU *)
and distro_of_lsb_release_distrib_id = function
  | "CoreOS" -> Some DISTRO_COREOS
  | "LinuxMint" -> Some DISTRO_LINUX_MINT
  | "Mageia" -> Some DISTRO_MAGEIA
  | "Ubuntu" -> Some DISTRO_UBUNTU
  | value ->
     eprintf "lsb-release: unknown DISTRIB_ID=%s\n" value;
     None

and parse_suse_release release_file data =
  let chroot = Chroot.create ~name:"parse_suse_release" () in
  let lines = Chroot.f chroot read_small_file release_file in

  match lines with
  | None
  | Some [] -> false
  | Some lines ->
     (* First line is dist release name. *)
     let product_name = List.hd lines in
     data.product_name <- Some product_name;

     (* Match SLES first because openSuSE regex overlaps some SLES
      * release strings.
      *)
     if PCRE.matches re_sles product_name ||
        PCRE.matches re_nld product_name then (
       (* Second line contains version string. *)
       let major =
         if List.length lines >= 2 then (
           let line = List.nth lines 1 in
           if PCRE.matches re_sles_version line then
             Some (int_of_string (PCRE.sub 1))
           else None
         )
         else None in

       (* Third line contains service pack string. *)
       let minor =
         if List.length lines >= 3 then (
           let line = List.nth lines 2 in
           if PCRE.matches re_sles_patchlevel line then
             Some (int_of_string (PCRE.sub 1))
           else None
         )
         else None in

       let version =
         match major, minor with
         | Some major, Some minor -> Some (major, minor)
         | Some major, None -> Some (major, 0)
         | None, Some _ | None, None -> None in

       data.distro <- Some DISTRO_SLES;
       data.version <- version
     )
     else if PCRE.matches re_opensuse product_name then (
       (* Second line contains version string. *)
       if List.length lines >= 2 then (
         let line = List.nth lines 1 in
         parse_version_from_major_minor line data
       );

       data.distro <- Some DISTRO_OPENSUSE
     );

     true

(* Parse any generic /etc/x-release file.
 *
 * The optional regular expression which may match 0, 1 or 2
 * substrings, which are used as the major and minor numbers.
 *
 * The fixed distro is always set, and the product name is
 * set to the first line of the release file.
 *)
and parse_generic ?rex distro release_file data =
  let chroot = Chroot.create ~name:"parse_generic" () in
  let product_name =
    Chroot.f chroot (
      fun file ->
        if not (is_small_file file) then (
          eprintf "%s: not a regular file or too large\n" file;
          ""
        )
        else
          read_first_line_from_file file
  ) release_file in
  if product_name = "" then
    false
  else (
    if verbose () then
      eprintf "parse_generic: product_name = %s\n%!" product_name;

    data.product_name <- Some product_name;
    data.distro <- Some distro;

    (match rex with
     | Some rex ->
        (* If ~rex was supplied, then it must match the release file,
         * else the parsing fails.
         *)
        if PCRE.matches rex product_name then (
          (* Although it's not documented, matched_group raises
           * Invalid_argument if called with an unknown group number.
           *)
          let major =
            try Some (int_of_string (PCRE.sub 1))
            with Not_found | Invalid_argument _ | Failure _ -> None in
          let minor =
            try Some (int_of_string (PCRE.sub 2))
            with Not_found | Invalid_argument _ | Failure _ -> None in
          (match major, minor with
           | None, None -> ()
           | None, Some _ -> ()
           | Some major, None -> data.version <- Some (major, 0)
           | Some major, Some minor -> data.version <- Some (major, minor)
          );
          true
        )
        else
          false (* ... else the parsing fails. *)

     | None ->
        (* However if no ~rex was supplied, then we make a best
         * effort attempt to parse a version number, but don't
         * fail if one cannot be found.
         *)
        parse_version_from_major_minor product_name data;
        true
    )
  )

(* The list of release file tests that we run for Linux root filesystems.
 * This is processed in order.
 *
 * For each test, first we check if the named release file exists.
 * If so, the parse function is called.  If not, we go on to the next
 * test.
 *
 * Each parse function should return true or false.  If a parse function
 * returns true, then we finish, else if it returns false then we continue
 * to the next test.
 *)
type parse_function = string -> inspection_data -> bool
type tests = (string * parse_function) list

let linux_root_tests : tests = [
  (* systemd distros include /etc/os-release which is reasonably
   * standardized.  This entry should be first.
   *)
  "/etc/os-release",     parse_os_release;
  (* LSB is also a reasonable standard.  This entry should be second. *)
  "/etc/lsb-release",    parse_lsb_release;

  (* Now we enter the Wild West ... *)

  (* OpenMandriva includes a [/etc/redhat-release] symlink, hence their
   * checks need to be performed before the Red-Hat one.
   *)
  "/etc/openmandriva-release", parse_generic ~rex:re_openmandriva
                                             DISTRO_OPENMANDRIVA;

  (* RHEL-based distros include a [/etc/redhat-release] file, hence their
   * checks need to be performed before the Red-Hat one.
   *)
  "/etc/oracle-release", parse_generic ~rex:re_oracle_linux_old
                                       DISTRO_ORACLE_LINUX;
  "/etc/oracle-release", parse_generic ~rex:re_oracle_linux
                                       DISTRO_ORACLE_LINUX;
  "/etc/oracle-release", parse_generic ~rex:re_oracle_linux_no_minor
                                       DISTRO_ORACLE_LINUX;
  "/etc/centos-release", parse_generic ~rex:re_centos_old
                                       DISTRO_CENTOS;
  "/etc/centos-release", parse_generic ~rex:re_centos
                                       DISTRO_CENTOS;
  "/etc/centos-release", parse_generic ~rex:re_centos_no_minor
                                       DISTRO_CENTOS;
  "/etc/rocky-release", parse_generic ~rex:re_rocky
                                       DISTRO_ROCKY;
  "/etc/rocky-release", parse_generic ~rex:re_rocky_no_minor
                                       DISTRO_ROCKY;
  "/etc/altlinux-release", parse_generic DISTRO_ALTLINUX;
  "/etc/redhat-release", parse_generic ~rex:re_fedora
                                       DISTRO_FEDORA;
  "/etc/redhat-release", parse_generic ~rex:re_rhel_old
                                       DISTRO_RHEL;
  "/etc/redhat-release", parse_generic ~rex:re_rhel
                                       DISTRO_RHEL;
  "/etc/redhat-release", parse_generic ~rex:re_rhel_no_minor
                                       DISTRO_RHEL;
  "/etc/redhat-release", parse_generic ~rex:re_centos_old
                                       DISTRO_CENTOS;
  "/etc/redhat-release", parse_generic ~rex:re_centos
                                       DISTRO_CENTOS;
  "/etc/redhat-release", parse_generic ~rex:re_centos_no_minor
                                       DISTRO_CENTOS;
  "/etc/redhat-release", parse_generic ~rex:re_rocky
                                       DISTRO_ROCKY;
  "/etc/redhat-release", parse_generic ~rex:re_rocky_no_minor
                                       DISTRO_ROCKY;
  "/etc/redhat-release", parse_generic ~rex:re_scientific_linux_old
                                       DISTRO_SCIENTIFIC_LINUX;
  "/etc/redhat-release", parse_generic ~rex:re_scientific_linux
                                       DISTRO_SCIENTIFIC_LINUX;
  "/etc/redhat-release", parse_generic ~rex:re_scientific_linux_no_minor
                                       DISTRO_SCIENTIFIC_LINUX;

  (* If there's an /etc/redhat-release file, but nothing above
   * matches, then it is a generic Red Hat-based distro.
   *)
  "/etc/redhat-release", parse_generic DISTRO_REDHAT_BASED;
  "/etc/redhat-release",
  (fun _ data -> data.distro <- Some DISTRO_REDHAT_BASED; true);

  "/etc/debian_version", parse_generic DISTRO_DEBIAN;
  "/etc/pardus-release", parse_generic DISTRO_PARDUS;

  (* /etc/arch-release file is empty and I can't see a way to
   * determine the actual release or product string.
   *)
  "/etc/arch-release",
  (fun _ data -> data.distro <- Some DISTRO_ARCHLINUX; true);

  "/etc/gentoo-release", parse_generic DISTRO_GENTOO;
  "/etc/meego-release", parse_generic DISTRO_MEEGO;
  "/etc/slackware-version", parse_generic DISTRO_SLACKWARE;
  "/etc/ttylinux-target", parse_generic DISTRO_TTYLINUX;

  "/etc/SuSE-release", parse_suse_release;
  "/etc/SuSE-release",
  (fun _ data -> data.distro <- Some DISTRO_SUSE_BASED; true);

  "/etc/cirros/version", parse_generic DISTRO_CIRROS;
  "/etc/br-version",
  (fun release_file data ->
    let distro =
      if Is.is_file ~followsymlinks:true "/usr/share/cirros/logo" then
        DISTRO_CIRROS
      else
        DISTRO_BUILDROOT in
    (* /etc/br-version has the format YYYY.MM[-git/hg/svn release] *)
    parse_generic distro release_file data);

  "/etc/alpine-release", parse_generic DISTRO_ALPINE_LINUX;
  "/etc/frugalware-release", parse_generic ~rex:re_frugalware
                                           DISTRO_FRUGALWARE;
  "/etc/pld-release", parse_generic ~rex:re_pldlinux
                                    DISTRO_PLD_LINUX;
]

let rec check_tests data = function
  | (release_file, parse_fun) :: tests ->
     if verbose () then
       eprintf "check_tests: checking %s\n%!" release_file;
     if Is.is_file ~followsymlinks:true release_file then (
       if parse_fun release_file data then () (* true => finished *)
       else check_tests data tests
     ) else check_tests data tests
  | [] -> ()

let rec check_linux_root mountable data =
  let os_type = OS_TYPE_LINUX in
  data.os_type <- Some os_type;

  check_tests data linux_root_tests;

  data.arch <- check_architecture ();
  data.fstab <-
    Inspect_fs_unix_fstab.check_fstab ~mdadm_conf:true mountable os_type;
  data.hostname <- check_hostname_linux ()

and check_architecture () =
  let rec loop = function
    | [] -> None
    | bin :: bins ->
       (* Allow symlinks when checking the binaries:,so in case they are
        * relative ones (which can be resolved within the same partition),
        * then we can check the architecture of their target.
        *)
       if Is.is_file ~followsymlinks:true bin then (
         try
           let resolved = Realpath.realpath bin in
           let arch = Filearch.file_architecture resolved in
           Some arch
         with exn ->
           if verbose () then
             eprintf "check_architecture: %s: %s\n%!" bin
                     (Printexc.to_string exn);
           loop bins
       )
       else
         loop bins
  in
  loop arch_binaries

and check_hostname_linux () =
  (* Red Hat-derived would be in /etc/sysconfig/network or
   * /etc/hostname (RHEL 7+, F18+).  Debian-derived in the file
   * /etc/hostname.  Very old Debian and SUSE use /etc/HOSTNAME.
   * It's best to just look for each of these files in turn, rather
   * than try anything clever based on distro.
   *)
  let rec loop = function
    | [] -> None
    | filename :: rest ->
       match check_hostname_from_file filename with
       | Some hostname -> Some hostname
       | None -> loop rest
  in
  let hostname = loop [ "/etc/HOSTNAME"; "/etc/hostname" ] in
  match hostname with
  | (Some _) as hostname -> hostname
  | None ->
     if Is.is_file "/etc/sysconfig/network" then
       with_augeas ~name:"check_hostname_from_sysconfig_network"
                   ["/etc/sysconfig/network"]
                   check_hostname_from_sysconfig_network
     else
       None

(* Parse the hostname where it is stored directly in a file.
 *
 * For /etc/hostname:
 * "The file should contain a single newline-terminated hostname
 * string. Comments (lines starting with a "#") are ignored."
 * [https://www.freedesktop.org/software/systemd/man/hostname.html]
 *
 * For other hostname files the exact format is not clear, but
 * hostnames cannot begin with "#" and cannot be empty, so ignoring
 * those lines seems safe.
 *)
and check_hostname_from_file filename =
  let chroot =
    let name = sprintf "check_hostname_from_file: %s" filename in
    Chroot.create ~name () in

  let hostname = Chroot.f chroot read_small_file filename in

  let keep_line line = line <> "" && not (String.is_prefix line "#") in
  let lines = Option.map (List.filter keep_line) hostname in
  match lines with
  | None | Some [] -> None
  | Some (hostname :: _) -> Some hostname

(* Parse the hostname from /etc/sysconfig/network.  This must be
 * called from the 'with_augeas' wrapper.  Note that F18+ and
 * RHEL7+ use /etc/hostname just like Debian.
 *)
and check_hostname_from_sysconfig_network aug =
  (* Errors here are not fatal (RHBZ#726739), since it could be
   * just missing HOSTNAME field in the file.
   *)
  aug_get_noerrors aug "/files/etc/sysconfig/network/HOSTNAME"

(* The currently mounted device looks like a Linux /usr. *)
let check_linux_usr data =
  data.os_type <- Some OS_TYPE_LINUX;

  if Is.is_file "/lib/os-release" ~followsymlinks:true then
    ignore (parse_os_release "/lib/os-release" data);

  (match check_architecture () with
   | None -> ()
   | (Some _) as arch -> data.arch <- arch
  )

(* The currently mounted device is a CoreOS root. From this partition we can
 * only determine the hostname. All immutable OS files are under a separate
 * read-only /usr partition.
 *)
let check_coreos_root mountable data =
  data.os_type <- Some OS_TYPE_LINUX;
  data.distro <- Some DISTRO_COREOS;

  (* Determine hostname. *)
  data.hostname <- check_hostname_linux ();

  (* CoreOS does not contain /etc/fstab to determine the mount points.
   * Associate this filesystem with the "/" mount point.
   *)
  data.fstab <- [ mountable, "/" ]

(* The currently mounted device looks like a CoreOS /usr. In CoreOS
 * the read-only /usr contains the OS version. The /etc/os-release is a
 * link to /usr/share/coreos/os-release.
 *)
let check_coreos_usr mountable data =
  data.os_type <- Some OS_TYPE_LINUX;
  data.distro <- Some DISTRO_COREOS;

  if Is.is_file "/lib/os-release" ~followsymlinks:true then
    ignore (parse_os_release "/lib/os-release" data)
  else if Is.is_file "/share/coreos/lsb-release" ~followsymlinks:true then
    ignore (parse_lsb_release "/share/coreos/lsb-release" data);

  (* Determine the architecture. *)
  (match check_architecture () with
   | None -> ()
   | (Some _) as arch -> data.arch <- arch
  );

  (* CoreOS does not contain /etc/fstab to determine the mount points.
   * Associate this filesystem with the "/usr" mount point.
   *)
  data.fstab <- [ mountable, "/usr" ]

let rec check_freebsd_root mountable data =
  let os_type = OS_TYPE_FREEBSD and distro = DISTRO_FREEBSD in
  data.os_type <- Some os_type;
  data.distro <- Some distro;

  (* FreeBSD has no authoritative version file.  The version number is
   * in /etc/motd, which the system administrator might edit, but
   * we'll use that anyway.
   *)
  if Is.is_file "/etc/motd" ~followsymlinks:true then
    ignore (parse_generic distro "/etc/motd" data);

  (* Determine the architecture. *)
  data.arch <- check_architecture ();
  (* We already know /etc/fstab exists because it's part of the test
   * in the caller.
   *)
  data.fstab <- Inspect_fs_unix_fstab.check_fstab mountable os_type;
  data.hostname <- check_hostname_freebsd ()

(* Parse the hostname from /etc/rc.conf.  On FreeBSD and NetBSD
 * this file contains comments, blank lines and:
 *   hostname="freebsd8.example.com"
 *   ifconfig_re0="DHCP"
 *   keymap="uk.iso"
 *   sshd_enable="YES"
 *)
and check_hostname_freebsd () =
  let chroot = Chroot.create ~name:"check_hostname_freebsd" () in
  let filename = "/etc/rc.conf" in

  try
    let lines = Chroot.f chroot read_small_file filename in
    let lines =
      match lines with None -> raise Not_found | Some lines -> lines in
    let rec loop = function
      | [] ->
         raise Not_found
      | line :: _ when String.is_prefix line "hostname=\"" ||
                       String.is_prefix line "hostname='" ->
         let len = String.length line - 10 - 1 in
         String.sub line 10 len
      | line :: _ when String.is_prefix line "hostname=" ->
         let len = String.length line - 9 in
         String.sub line 9 len
      | _ :: lines ->
         loop lines
    in
    let hostname = loop lines in
    Some hostname
  with
    Not_found -> None

let rec check_netbsd_root mountable data =
  let os_type = OS_TYPE_NETBSD and distro = DISTRO_NETBSD in
  data.os_type <- Some os_type;
  data.distro <- Some distro;

  if Is.is_file "/etc/release" ~followsymlinks:true then
    ignore (parse_generic ~rex:re_netbsd distro "/etc/release" data);

  (* Determine the architecture. *)
  data.arch <- check_architecture ();
  (* We already know /etc/fstab exists because it's part of the test
   * in the caller.
   *)
  data.fstab <- Inspect_fs_unix_fstab.check_fstab mountable os_type;
  data.hostname <- check_hostname_freebsd ()

and check_hostname_netbsd () = check_hostname_freebsd ()

let rec check_openbsd_root mountable data =
  let os_type = OS_TYPE_FREEBSD and distro = DISTRO_FREEBSD in
  data.os_type <- Some os_type;
  data.distro <- Some distro;

  (* The first line of /etc/motd gets automatically updated at boot. *)
  if Is.is_file "/etc/motd" ~followsymlinks:true then
    ignore (parse_generic distro "/etc/motd" data);

  (* Before the first boot, the first line will look like this:
   *
   * OpenBSD ?.? (UNKNOWN)
   *
   * The previous C code used to check for this case explicitly,
   * but in this code, parse_generic should be unable to extract
   * any version and so should return with [data.version = None].
   *)

  (* Determine the architecture. *)
  data.arch <- check_architecture ();
  (* We already know /etc/fstab exists because it's part of the test
   * in the caller.
   *)
  data.fstab <- Inspect_fs_unix_fstab.check_fstab mountable os_type;
  data.hostname <- check_hostname_freebsd ()

and check_hostname_openbsd () =
  check_hostname_from_file "/etc/myname"

let hurd_root_tests : tests = [
  (* Newer distros include /etc/os-release which is reasonably
   * standardized.  This entry should be first.
   *)
  "/etc/os-release",     parse_os_release;
  "/etc/debian_version", parse_generic DISTRO_DEBIAN;
  (* Arch Hurd also exists, but inconveniently it doesn't have
   * the normal /etc/arch-release file.  XXX
   *)
]

(* The currently mounted device may be a Hurd root.  Hurd has distros
 * just like Linux.
 *)
let rec check_hurd_root mountable data =
  let os_type = OS_TYPE_HURD in
  data.os_type <- Some os_type;

  check_tests data hurd_root_tests;

  (* Determine the architecture. *)
  data.arch <- check_architecture ();
  (* We already know /etc/fstab exists because it's part of the test
   * in the caller.
   *)
  data.fstab <- Inspect_fs_unix_fstab.check_fstab mountable os_type;
  data.hostname <- check_hostname_hurd ()

and check_hostname_hurd () = check_hostname_linux ()

let rec check_minix_root data =
  let os_type = OS_TYPE_MINIX in
  data.os_type <- Some os_type;

  if Is.is_file "/etc/version" ~followsymlinks:true then (
    ignore (parse_generic ~rex:re_minix DISTRO_MEEGO (* XXX unset below *)
                          "/etc/version" data);
    data.distro <- None
  );

  (* Determine the architecture. *)
  data.arch <- check_architecture ();
  (* TODO: enable fstab inspection once resolve_fstab_device
   * implements the proper mapping from the Minix device names
   * to the appliance names.
   *)
  data.hostname <- check_hostname_minix ()

and check_hostname_minix () =
  check_hostname_from_file "/etc/hostname.file"
