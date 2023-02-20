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

type fs = {
  fs_location : location;
  role : role;             (** Special cases: root filesystem or /usr *)
}
and root = {
  root_location : location;
  inspection_data : inspection_data;
}
and location = {
  mountable : Mountable.t; (** The device name or other mountable object.*)
  vfs_type : string;       (** Returned from [vfs_type] API. *)
}

and role =
  | RoleRoot of inspection_data
  | RoleUsr of inspection_data
  | RoleSwap
  | RoleOther
and inspection_data = {
  mutable os_type : os_type option;
  mutable distro : distro option;
  mutable package_format : package_format option;
  mutable package_management : package_management option;
  mutable product_name : string option;
  mutable product_variant : string option;
  mutable version : version option;
  mutable arch : string option;
  mutable hostname : string option;
  mutable build_id : string option;
  mutable fstab : fstab_entry list;
  mutable windows_systemroot : string option;
  mutable windows_software_hive : string option;
  mutable windows_system_hive : string option;
  mutable windows_current_control_set : string option;
  mutable drive_mappings : drive_mapping list;
}
and os_type =
  | OS_TYPE_DOS
  | OS_TYPE_FREEBSD
  | OS_TYPE_HURD
  | OS_TYPE_LINUX
  | OS_TYPE_MINIX
  | OS_TYPE_NETBSD
  | OS_TYPE_OPENBSD
  | OS_TYPE_WINDOWS
and distro =
  | DISTRO_ALPINE_LINUX
  | DISTRO_ALTLINUX
  | DISTRO_ARCHLINUX
  | DISTRO_BUILDROOT
  | DISTRO_CENTOS
  | DISTRO_CIRROS
  | DISTRO_COREOS
  | DISTRO_DEBIAN
  | DISTRO_FEDORA
  | DISTRO_FREEBSD
  | DISTRO_FREEDOS
  | DISTRO_FRUGALWARE
  | DISTRO_GENTOO
  | DISTRO_KALI_LINUX
  | DISTRO_KYLIN
  | DISTRO_LINUX_MINT
  | DISTRO_MAGEIA
  | DISTRO_MANDRIVA
  | DISTRO_MEEGO
  | DISTRO_MSDOS
  | DISTRO_NEOKYLIN
  | DISTRO_NETBSD
  | DISTRO_OPENBSD
  | DISTRO_OPENMANDRIVA
  | DISTRO_OPENSUSE
  | DISTRO_ORACLE_LINUX
  | DISTRO_PARDUS
  | DISTRO_PLD_LINUX
  | DISTRO_REDHAT_BASED
  | DISTRO_RHEL
  | DISTRO_ROCKY
  | DISTRO_SCIENTIFIC_LINUX
  | DISTRO_SLACKWARE
  | DISTRO_SLES
  | DISTRO_SUSE_BASED
  | DISTRO_TTYLINUX
  | DISTRO_UBUNTU
  | DISTRO_VOID_LINUX
  | DISTRO_WINDOWS
and package_format =
  | PACKAGE_FORMAT_APK
  | PACKAGE_FORMAT_DEB
  | PACKAGE_FORMAT_EBUILD
  | PACKAGE_FORMAT_PACMAN
  | PACKAGE_FORMAT_PISI
  | PACKAGE_FORMAT_PKGSRC
  | PACKAGE_FORMAT_RPM
  | PACKAGE_FORMAT_XBPS
and package_management =
  | PACKAGE_MANAGEMENT_APK
  | PACKAGE_MANAGEMENT_APT
  | PACKAGE_MANAGEMENT_DNF
  | PACKAGE_MANAGEMENT_PACMAN
  | PACKAGE_MANAGEMENT_PISI
  | PACKAGE_MANAGEMENT_PORTAGE
  | PACKAGE_MANAGEMENT_UP2DATE
  | PACKAGE_MANAGEMENT_URPMI
  | PACKAGE_MANAGEMENT_XBPS
  | PACKAGE_MANAGEMENT_YUM
  | PACKAGE_MANAGEMENT_ZYPPER
and version = int * int
and fstab_entry = Mountable.t * string (* mountable, mountpoint *)
and drive_mapping = string * string (* drive name, device *)

let rec string_of_fs { fs_location = location; role } =
  sprintf "fs: %s role: %s\n"
          (string_of_location location)
          (match role with
           | RoleRoot data -> "root\n" ^ string_of_inspection_data data
           | RoleUsr data -> "usr\n" ^ string_of_inspection_data data
           | RoleSwap -> "swap"
           | RoleOther -> "other")

and string_of_location { mountable ; vfs_type } =
  sprintf "%s (%s)" (Mountable.to_string mountable) vfs_type

and string_of_root { root_location; inspection_data } =
  sprintf "%s:\n%s"
          (string_of_location root_location)
          (string_of_inspection_data inspection_data)

and string_of_inspection_data data =
  let b = Buffer.create 1024 in
  let bpf fs = bprintf b fs in
  Option.iter (fun v -> bpf "    type: %s\n" (string_of_os_type v))
             data.os_type;
  Option.iter (fun v -> bpf "    distro: %s\n" (string_of_distro v))
             data.distro;
  Option.iter (fun v -> bpf "    package_format: %s\n" (string_of_package_format v))
             data.package_format;
  Option.iter (fun v -> bpf "    package_management: %s\n" (string_of_package_management v))
             data.package_management;
  Option.iter (fun v -> bpf "    product_name: %s\n" v)
             data.product_name;
  Option.iter (fun v -> bpf "    product_variant: %s\n" v)
             data.product_variant;
  Option.iter (fun (major, minor) -> bpf "    version: %d.%d\n" major minor)
             data.version;
  Option.iter (fun v -> bpf "    arch: %s\n" v)
             data.arch;
  Option.iter (fun v -> bpf "    hostname: %s\n" v)
             data.hostname;
  Option.iter (fun v -> bpf "    build ID: %s\n" v)
             data.build_id;
  if data.fstab <> [] then (
    let v = List.map (
      fun (a, b) -> sprintf "(%s, %s)" (Mountable.to_string a) b
    ) data.fstab in
    bpf "    fstab: [%s]\n" (String.concat ", " v)
  );
  Option.iter (fun v -> bpf "    windows_systemroot: %s\n" v)
             data.windows_systemroot;
  Option.iter (fun v -> bpf "    windows_software_hive: %s\n" v)
             data.windows_software_hive;
  Option.iter (fun v -> bpf "    windows_system_hive: %s\n" v)
             data.windows_system_hive;
  Option.iter (fun v -> bpf "    windows_current_control_set: %s\n" v)
             data.windows_current_control_set;
  if data.drive_mappings <> [] then (
    let v =
      List.map (fun (a, b) -> sprintf "(%s, %s)" a b) data.drive_mappings in
    bpf "    drive_mappings: [%s]\n" (String.concat ", " v)
  );
  Buffer.contents b

and string_of_os_type = function
  | OS_TYPE_DOS -> "dos"
  | OS_TYPE_FREEBSD -> "freebsd"
  | OS_TYPE_HURD -> "hurd"
  | OS_TYPE_LINUX -> "linux"
  | OS_TYPE_MINIX -> "minix"
  | OS_TYPE_NETBSD -> "netbsd"
  | OS_TYPE_OPENBSD -> "openbsd"
  | OS_TYPE_WINDOWS -> "windows"

and string_of_distro = function
  | DISTRO_ALPINE_LINUX -> "alpinelinux"
  | DISTRO_ALTLINUX -> "altlinux"
  | DISTRO_ARCHLINUX -> "archlinux"
  | DISTRO_BUILDROOT -> "buildroot"
  | DISTRO_CENTOS -> "centos"
  | DISTRO_CIRROS -> "cirros"
  | DISTRO_COREOS -> "coreos"
  | DISTRO_DEBIAN -> "debian"
  | DISTRO_FEDORA -> "fedora"
  | DISTRO_FREEBSD -> "freebsd"
  | DISTRO_FREEDOS -> "freedos"
  | DISTRO_FRUGALWARE -> "frugalware"
  | DISTRO_GENTOO -> "gentoo"
  | DISTRO_KALI_LINUX -> "kalilinux"
  | DISTRO_KYLIN -> "kylin"
  | DISTRO_LINUX_MINT -> "linuxmint"
  | DISTRO_MAGEIA -> "mageia"
  | DISTRO_MANDRIVA -> "mandriva"
  | DISTRO_MEEGO -> "meego"
  | DISTRO_MSDOS -> "msdos"
  | DISTRO_NEOKYLIN -> "neokylin"
  | DISTRO_NETBSD -> "netbsd"
  | DISTRO_OPENBSD -> "openbsd"
  | DISTRO_OPENMANDRIVA -> "openmandriva"
  | DISTRO_OPENSUSE -> "opensuse"
  | DISTRO_ORACLE_LINUX -> "oraclelinux"
  | DISTRO_PARDUS -> "pardus"
  | DISTRO_PLD_LINUX -> "pldlinux"
  | DISTRO_REDHAT_BASED -> "redhat-based"
  | DISTRO_RHEL -> "rhel"
  | DISTRO_ROCKY -> "rocky"
  | DISTRO_SCIENTIFIC_LINUX -> "scientificlinux"
  | DISTRO_SLACKWARE -> "slackware"
  | DISTRO_SLES -> "sles"
  | DISTRO_SUSE_BASED -> "suse-based"
  | DISTRO_TTYLINUX -> "ttylinux"
  | DISTRO_UBUNTU -> "ubuntu"
  | DISTRO_VOID_LINUX -> "voidlinux"
  | DISTRO_WINDOWS -> "windows"

and string_of_package_format = function
  | PACKAGE_FORMAT_APK -> "apk"
  | PACKAGE_FORMAT_DEB -> "deb"
  | PACKAGE_FORMAT_EBUILD -> "ebuild"
  | PACKAGE_FORMAT_PACMAN -> "pacman"
  | PACKAGE_FORMAT_PISI -> "pisi"
  | PACKAGE_FORMAT_PKGSRC -> "pkgsrc"
  | PACKAGE_FORMAT_RPM -> "rpm"
  | PACKAGE_FORMAT_XBPS -> "xbps"

and string_of_package_management = function
  | PACKAGE_MANAGEMENT_APK -> "apk"
  | PACKAGE_MANAGEMENT_APT -> "apt"
  | PACKAGE_MANAGEMENT_DNF -> "dnf"
  | PACKAGE_MANAGEMENT_PACMAN -> "pacman"
  | PACKAGE_MANAGEMENT_PISI -> "pisi"
  | PACKAGE_MANAGEMENT_PORTAGE -> "portage"
  | PACKAGE_MANAGEMENT_UP2DATE -> "up2date"
  | PACKAGE_MANAGEMENT_URPMI -> "urpmi"
  | PACKAGE_MANAGEMENT_XBPS -> "xbps"
  | PACKAGE_MANAGEMENT_YUM -> "yum"
  | PACKAGE_MANAGEMENT_ZYPPER -> "zypper"

let null_inspection_data = {
  os_type = None;
  distro = None;
  package_format = None;
  package_management = None;
  product_name = None;
  product_variant = None;
  version = None;
  arch = None;
  hostname = None;
  build_id = None;
  fstab = [];
  windows_systemroot = None;
  windows_software_hive = None;
  windows_system_hive = None;
  windows_current_control_set = None;
  drive_mappings = [];
}
let null_inspection_data () = { null_inspection_data with os_type = None }

let merge_inspection_data child parent =
  let merge child parent = if parent = None then child else parent in

  parent.os_type <-         merge child.os_type parent.os_type;
  parent.distro <-          merge child.distro parent.distro;
  parent.package_format <-  merge child.package_format parent.package_format;
  parent.package_management <-
    merge child.package_management parent.package_management;
  parent.product_name <-    merge child.product_name parent.product_name;
  parent.product_variant <- merge child.product_variant parent.product_variant;
  parent.version <-         merge child.version parent.version;
  parent.arch <-            merge child.arch parent.arch;
  parent.hostname <-        merge child.hostname parent.hostname;
  parent.build_id <-        merge child.build_id parent.build_id;
  parent.fstab <-           child.fstab @ parent.fstab;
  parent.windows_systemroot <-
    merge child.windows_systemroot parent.windows_systemroot;
  parent.windows_software_hive <-
    merge child.windows_software_hive parent.windows_software_hive;
  parent.windows_system_hive <-
    merge child.windows_system_hive parent.windows_system_hive;
  parent.windows_current_control_set <-
    merge child.windows_current_control_set parent.windows_current_control_set;

  (* This is what the old C code did, but I doubt that it's correct. *)
  parent.drive_mappings <-  child.drive_mappings @ parent.drive_mappings

let merge child_fs parent_fs =
  let inspection_data_of_fs = function
    | { role = RoleRoot data }
    | { role = RoleUsr data } -> data
    | { role = (RoleSwap|RoleOther) } -> null_inspection_data ()
  in

  match parent_fs with
  | { role = RoleRoot parent_data } ->
     merge_inspection_data (inspection_data_of_fs child_fs) parent_data
  | { role = RoleUsr parent_data } ->
     merge_inspection_data (inspection_data_of_fs child_fs) parent_data
  | { role = (RoleSwap|RoleOther) } ->
     ()

let inspect_fses = ref []
