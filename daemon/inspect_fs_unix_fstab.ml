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

let re_cciss = PCRE.compile "^/dev/(cciss/c\\d+d\\d+)(?:p(\\d+))?$"
let re_diskbyid = PCRE.compile "^/dev/disk/by-id/.*-part(\\d+)$"
let re_freebsd_gpt = PCRE.compile "^/dev/(ada{0,1}|vtbd)(\\d+)p(\\d+)$"
let re_freebsd_mbr = PCRE.compile "^/dev/(ada{0,1}|vtbd)(\\d+)s(\\d+)([a-z])$"
let re_hurd_dev = PCRE.compile "^/dev/(h)d(\\d+)s(\\d+)$"
let re_mdN = PCRE.compile "^/dev/md\\d+$"
let re_netbsd_dev = PCRE.compile "^/dev/(l|s)d([0-9])([a-z])$"
let re_openbsd_dev = PCRE.compile "^/dev/(s|w)d([0-9])([a-z])$"
let re_openbsd_duid = PCRE.compile "^[0-9a-f]{16}\\.[a-z]"
let re_xdev = PCRE.compile "^/dev/(h|s|v|xv)d([a-z]+)(\\d*)$"

let rec check_fstab ?(mdadm_conf = false) (root_mountable : Mountable.t)
                    os_type =
  let mdadmfiles =
    if mdadm_conf then ["/etc/mdadm.conf"; "/etc/mdadm/mdadm.conf"] else [] in
  let configfiles = "/etc/fstab" :: mdadmfiles in

  with_augeas ~name:"check_fstab_aug"
              configfiles (check_fstab_aug mdadm_conf root_mountable os_type)

and check_fstab_aug mdadm_conf root_mountable os_type aug =
  (* Generate a map of MD device paths listed in mdadm.conf
   * to MD device paths in the guestfs appliance.
   *)
  let md_map = if mdadm_conf then map_md_devices aug else StringMap.empty in

  let path = "/files/etc/fstab/*[label() != '#comment']" in
  let entries = aug_matches_noerrors aug path in
  List.filter_map (check_fstab_entry md_map root_mountable os_type aug) entries

and check_fstab_entry md_map root_mountable os_type aug entry =
  with_return (fun {return} ->
    if verbose () then
      eprintf "check_fstab_entry: augeas path: %s\n%!" entry;

    let is_bsd =
      match os_type with
      | OS_TYPE_FREEBSD | OS_TYPE_NETBSD | OS_TYPE_OPENBSD -> true
      | OS_TYPE_DOS | OS_TYPE_HURD | OS_TYPE_LINUX | OS_TYPE_MINIX
      | OS_TYPE_WINDOWS -> false in

    let spec = aug_get_noerrors aug (entry ^ "/spec") in
    let spec =
      match spec with
      | None -> return None
      | Some spec -> spec in

    if verbose () then eprintf "check_fstab_entry: spec=%s\n%!" spec;

    (* Ignore /dev/fd (floppy disks) (RHBZ#642929) and CD-ROM drives.
     *
     * /dev/iso9660/FREEBSD_INSTALL can be found in FreeBSD's
     * installation discs.
     *)
    if (String.is_prefix spec "/dev/fd" &&
        String.length spec >= 8 && Char.isdigit spec.[7]) ||
       (String.is_prefix spec "/dev/cd" &&
        String.length spec >= 8 && Char.isdigit spec.[7]) ||
       spec = "/dev/floppy" ||
       spec = "/dev/cdrom" ||
       String.is_prefix spec "/dev/iso9660/" then
      return None;

    let mp = aug_get_noerrors aug (entry ^ "/file") in
    let mp =
      match mp with
      | None -> return None
      | Some mp -> mp in

    (* Canonicalize the path, so "///usr//local//" -> "/usr/local" *)
    let mp = unix_canonical_path mp in

    if verbose () then eprintf "check_fstab_entry: mp=%s\n%!" mp;

    (* Ignore certain mountpoints. *)
    if String.is_prefix mp "/dev/" ||
       mp = "/dev" ||
       String.is_prefix mp "/media/" ||
       String.is_prefix mp "/proc/" ||
       mp = "/proc" ||
       String.is_prefix mp "/selinux/" ||
       mp = "/selinux" ||
       String.is_prefix mp "/sys/" ||
       mp = "/sys" then
      return None;

    let mountable =
      (* Resolve UUID= and LABEL= to the actual device. *)
      if String.is_prefix spec "UUID=" then (
        let uuid = String.sub spec 5 (String.length spec - 5) in
        let uuid = shell_unquote uuid in
        (* Just ignore the device if the UUID cannot be resolved. *)
        try
          Mountable.of_device (Findfs.findfs_uuid uuid)
        with
          Failure _ -> return None
      )
      else if String.is_prefix spec "LABEL=" then (
        let label = String.sub spec 6 (String.length spec - 6) in
        let label = shell_unquote label in
        (* Just ignore the device if the label cannot be resolved. *)
        try
          Mountable.of_device (Findfs.findfs_label label)
        with
          Failure _ -> return None
      )
      (* Resolve /dev/root to the current device.
       * Do the same for the / partition of the *BSD
       * systems, since the BSD -> Linux device
       * translation is not straight forward.
       *)
      else if spec = "/dev/root" || (is_bsd && mp = "/") then
        root_mountable
      (* Resolve guest block device names. *)
      else if String.is_prefix spec "/dev/" then
        resolve_fstab_device spec md_map os_type
      (* In OpenBSD's fstab you can specify partitions
       * on a disk by appending a period and a partition
       * letter to a Disklable Unique Identifier. The
       * DUID is a 16 hex digit field found in the
       * OpenBSD's altered BSD disklabel. For more info
       * see here:
       * http://www.openbsd.org/faq/faq14.html#intro
       *)
      else if PCRE.matches re_openbsd_duid spec then (
        let part = spec.[17] in
        (* We cannot peep into disklabels, we can only
         * assume that this is the first disk.
         *)
        let device = sprintf "/dev/sd0%c" part in
        resolve_fstab_device device md_map os_type
      )
      (* Ignore "/.swap" (Pardus) and pseudo-devices
       * like "tmpfs".  If we haven't resolved the device
       * successfully by this point, just ignore it.
       *)
      else
        return None in

    let vfstype = aug_get_noerrors aug (entry ^ "/vfstype") in
    let vfstype =
      match vfstype with
      | None -> return None
      | Some vfstype -> vfstype in
    if verbose () then eprintf "check_fstab_entry: vfstype=%s\n%!" vfstype;

    let mountable =
      if vfstype = "btrfs" then
        get_btrfs_mountable aug entry mountable
      else mountable in

    Some (mountable, mp)
  )

(* If an fstab entry corresponds to a btrfs filesystem, look for
 * the 'subvol' option and if it is present then return a btrfs
 * subvolume (else return the whole device).
 *)
and get_btrfs_mountable aug entry mountable =
  let device =
    match mountable with
    | { Mountable.m_type = Mountable.MountableDevice; m_device = device } ->
       Some device
    | { Mountable.m_type =
          (Mountable.MountablePath|Mountable.MountableBtrfsVol _) } ->
       None in

  match device with
  | None -> mountable
  | Some device ->
     let opts = aug_matches_noerrors aug (entry ^ "/opt") in
     let rec loop = function
       | [] -> mountable        (* no subvol, return whole device *)
       | opt :: opts ->
          let optname = aug_get_noerrors aug opt in
          match optname with
          | None -> loop opts
          | Some "subvol" ->
             let subvol = aug_get_noerrors aug (opt ^ "/value") in
             (match subvol with
              | None -> loop opts
              | Some subvol ->
                 Mountable.of_btrfsvol device subvol
             )
          | Some _ ->
             loop opts
     in
     loop opts

(* Get a map of md device names in mdadm.conf to their device names
 * in the appliance.
 *)
and map_md_devices aug =
  (* Get a map of md device uuids to their device names in the appliance. *)
  let uuid_map = map_app_md_devices () in

  (* Nothing to do if there are no md devices. *)
  if StringMap.is_empty uuid_map then StringMap.empty
  else (
    (* Get all arrays listed in mdadm.conf. *)
    let entries1 = aug_matches_noerrors aug "/files/etc/mdadm.conf/array" in
    let entries2 = aug_matches_noerrors aug "/files/etc/mdadm/mdadm.conf/array" in
    let entries = List.append entries1 entries2 in

    (* Log a debug entry if we've got md devices but nothing in mdadm.conf. *)
    if verbose () && entries = [] then
      eprintf "warning: appliance has MD devices, but augeas returned no array matches in mdadm.conf\n%!";

    List.fold_left (
      fun md_map entry ->
        try
          (* Get device name and uuid for each array. *)
          let dev = aug_get_noerrors aug (entry ^ "/devicename") in
          let uuid = aug_get_noerrors aug (entry ^ "/uuid") in
          let dev =
            match dev with None -> raise Not_found | Some dev -> dev in
          let uuid =
            match uuid with None -> raise Not_found | Some uuid -> uuid in

          (* Parse the uuid into an md_uuid structure so we can look
           * it up in the uuid_map.
           *)
          let uuid = parse_md_uuid uuid in

          let md = StringMap.find uuid uuid_map in

          (* If there's a corresponding uuid in the appliance, create
           * a new entry in the transitive map.
           *)
          StringMap.add dev md md_map
        with
          (* No Augeas devicename or uuid node found, or could not parse
           * uuid, or uuid not present in the uuid_map.
           *
           * This is not fatal, just ignore the entry.
           *)
          Not_found | Invalid_argument _ -> md_map
    ) StringMap.empty entries
  )

(* Create a mapping of uuids to appliance md device names. *)
and map_app_md_devices () =
  let mds = Md.list_md_devices () in
  List.fold_left (
    fun map md ->
      let detail = Md.md_detail md in

      try
        (* Find the value of the "uuid" key. *)
        let uuid = List.assoc "uuid" detail in
        let uuid = parse_md_uuid uuid in
        StringMap.add uuid md map
      with
        (* uuid not found, or could not be parsed - just ignore the entry *)
        Not_found | Invalid_argument _ -> map
  ) StringMap.empty mds

(* Taken from parse_uuid in mdadm.
 *
 * Raises Invalid_argument if the input is not an MD UUID.
 *)
and parse_md_uuid uuid =
  let len = String.length uuid in
  let out = Bytes.create len in
  let j = ref 0 in

  for i = 0 to len-1 do
    let c = uuid.[i] in
    if Char.isxdigit c then (
      Bytes.set out !j c;
      incr j
    )
    else if c = ':' || c = '.' || c = ' ' || c = '-' then
      ()
    else
      invalid_arg "parse_md_uuid: invalid character"
  done;

  if !j <> 32 then
    invalid_arg "parse_md_uuid: invalid length";

  Bytes.sub_string out 0 !j

(* Resolve block device name to the libguestfs device name, eg.
 * /dev/xvdb1 => /dev/vdb1; and /dev/mapper/VG-LV => /dev/VG/LV.  This
 * assumes that disks were added in the same order as they appear to
 * the real VM, which is a reasonable assumption to make.  Return
 * anything we don't recognize unchanged.
 *)
and resolve_fstab_device spec md_map os_type =
  (* In any case where we didn't match a device pattern or there was
   * another problem, return this default mountable derived from [spec].
   *)
  let default = Mountable.of_device spec in

  let debug_matching what =
    if verbose () then
      eprintf "resolve_fstab_device: %s matched %s\n%!" spec what
  in

  if String.is_prefix spec "/dev/mapper" then (
    debug_matching "/dev/mapper";
    (* LVM2 does some strange munging on /dev/mapper paths for VGs and
     * LVs which contain '-' character:
     *
     * ><fs> lvcreate LV--test VG--test 32
     * ><fs> debug ls /dev/mapper
     * VG----test-LV----test
     *
     * This makes it impossible to reverse those paths directly, so
     * we have implemented lvm_canonical_lv_name in the daemon.
     *)
    try
      match Lvm_utils.lv_canonical spec with
      | None -> Mountable.of_device spec
      | Some device -> Mountable.of_device device
    with
    (* Ignore devices that don't exist. (RHBZ#811872) *)
    | Unix.Unix_error (Unix.ENOENT, _, _) -> default
  )

  else if PCRE.matches re_xdev spec then (
    debug_matching "xdev";
    let typ = PCRE.sub 1
    and disk = PCRE.sub 2
    and part = PCRE.sub 3 in
    resolve_xdev typ disk part default
  )

  else if PCRE.matches re_cciss spec then (
    debug_matching "cciss";
    let disk = PCRE.sub 1
    and part = try Some (int_of_string (PCRE.sub 2)) with Not_found -> None in
    resolve_cciss disk part default
  )

  else if PCRE.matches re_mdN spec then (
    debug_matching "md<N>";
    try
      Mountable.of_device (StringMap.find spec md_map)
    with
    | Not_found -> default
  )

  else if PCRE.matches re_diskbyid spec then (
    debug_matching "diskbyid";
    let part = int_of_string (PCRE.sub 1) in
    resolve_diskbyid part default
  )

  else if PCRE.matches re_freebsd_gpt spec then (
    debug_matching "FreeBSD GPT";
    (* group 1 (type) is not used *)
    let disk = int_of_string (PCRE.sub 2)
    and part = int_of_string (PCRE.sub 3) in

    (* If the FreeBSD disk contains GPT partitions, the translation to Linux
     * device names is straight forward.  Partitions on a virtio disk are
     * prefixed with [vtbd].  IDE hard drives used to be prefixed with [ad]
     * and now prefixed with [ada].
     *)
    if disk >= 0 && disk <= 26 && part >= 0 && part <= 128 then (
      let dev = sprintf "/dev/sd%c%d"
                        (Char.chr (disk + Char.code 'a')) part in
      Mountable.of_device dev
    )
    else default
  )

  else if PCRE.matches re_freebsd_mbr spec then (
    debug_matching "FreeBSD MBR";
    (* group 1 (type) is not used *)
    let disk = int_of_string (PCRE.sub 2)
    and slice = int_of_string (PCRE.sub 3)
    (* partition number counting from 0: *)
    and part = Char.code (PCRE.sub 4).[0] - Char.code 'a' in

    (* FreeBSD MBR disks are organized quite differently.  See:
     * http://www.freebsd.org/doc/handbook/disk-organization.html
     * FreeBSD "partitions" are exposed as quasi-extended partitions
     * numbered from 5 in Linux.  I have no idea what happens when you
     * have multiple "slices" (the FreeBSD term for MBR partitions).
     *)

    (* Partition 'c' has the size of the enclosing slice.
     * Not mapped under Linux.
     *)
    let part = if part > 2 then part - 1 else part in

    if disk >= 0 && disk <= 26 &&
       slice > 0 && slice <= 1 (* > 4 .. see comment above *) &&
       part >= 0 && part < 25 then (
      let dev = sprintf "/dev/sd%c%d"
                        (Char.chr (disk + Char.code 'a')) (part + 5) in
      Mountable.of_device dev
    )
    else default
  )

  else if os_type = OS_TYPE_NETBSD && PCRE.matches re_netbsd_dev spec then (
    debug_matching "NetBSD";
    (* group 1 (type) is not used *)
    let disk = int_of_string (PCRE.sub 2)
    (* partition number counting from 0: *)
    and part = Char.code (PCRE.sub 3).[0] - Char.code 'a' in

    (* Partition 'c' is the disklabel partition and 'd' the hard disk itself.
     * Not mapped under Linux.
     *)
    let part = if part > 3 then part - 2 else part in

    if disk >= 0 && part >= 0 && part < 24 then (
      let dev = sprintf "/dev/sd%c%d"
                        (Char.chr (disk + Char.code 'a')) (part + 5) in
      Mountable.of_device dev
    )
    else default
  )

  else if os_type = OS_TYPE_OPENBSD && PCRE.matches re_openbsd_dev spec then (
    debug_matching "OpenBSD";
    (* group 1 (type) is not used *)
    let disk = int_of_string (PCRE.sub 2)
    (* partition number counting from 0: *)
    and part = Char.code (PCRE.sub 3).[0] - Char.code 'a' in

    (* Partition 'c' is the hard disk itself. Not mapped under Linux. *)
    let part = if part > 2 then part - 1 else part in

    (* In OpenBSD MAXPARTITIONS is defined to 16 for all architectures. *)
    if disk >= 0 && part >= 0 && part < 15 then (
      let dev = sprintf "/dev/sd%c%d"
                        (Char.chr (disk + Char.code 'a')) (part + 5) in
      Mountable.of_device dev
    )
    else default
  )

  else if PCRE.matches re_hurd_dev spec then (
    debug_matching "Hurd";
    let typ = PCRE.sub 1
    and disk = int_of_string (PCRE.sub 2)
    and part = PCRE.sub 3 in

    (* Hurd disk devices are like /dev/hdNsM, where hdN is the
     * N-th disk and M is the M-th partition on that disk.
     * Turn the disk number into a letter-based identifier, so
     * we can resolve it easily.
     *)
    let disk = sprintf "%c" (Char.chr (disk + Char.code 'a')) in

    resolve_xdev typ disk part default
  )

  else (
    debug_matching "no known device scheme";
    default
  )

(* type: (h|s|v|xv)
 * disk: [a-z]+
 * part: \d*
 *)
and resolve_xdev typ disk part default =
  let devices = Devsparts.list_devices () in
  let devices = Array.of_list devices in

  (* XXX Check any hints we were passed for a non-heuristic mapping.
   * The C code used hints here to map device names as known by
   * the library user (eg. from metadata) to libguestfs devices here.
   * However none of the libguestfs tools ever used this feature.
   * Nevertheless we should reimplement it at some point because
   * outside callers might require it, and it's a good idea in general.
   *)

  (* Guess the appliance device name if we didn't find a matching hint. *)
  let i = drive_index disk in
  if i >= 0 && i < Array.length devices then (
    let dev = Array.get devices i in
    let dev = dev ^ part in
    if is_partition dev then
      Mountable.of_device dev
    else
      default
  )
  else
    default

(* disk: (cciss/c\d+d\d+)
 * part: (\d+)?
 *)
and resolve_cciss disk part default =
  (* XXX Check any hints we were passed for a non-heuristic mapping.
   * The C code used hints here to map device names as known by
   * the library user (eg. from metadata) to libguestfs devices here.
   * However none of the libguestfs tools ever used this feature.
   * Nevertheless we should reimplement it at some point because
   * outside callers might require it, and it's a good idea in general.
   *)

  (* We don't try to guess mappings for cciss devices. *)
  default

(* For /dev/disk/by-id there is a limit to what we can do because
 * original SCSI ID information has likely been lost.  This
 * heuristic will only work for guests that have a single block
 * device.
 *
 * So the main task here is to make sure the assumptions above are
 * true.
 *
 * XXX Use hints from virt-p2v if available.
 * See also: https://bugzilla.redhat.com/show_bug.cgi?id=836573#c3
 *)
and resolve_diskbyid part default =
  let nr_devices = Devsparts.nr_devices () in

  (* If #devices isn't 1, give up trying to translate this fstab entry. *)
  if nr_devices <> 1 then
    default
  else (
    (* Make the partition name and check it exists. *)
    let dev = sprintf "/dev/sda%d" part in
    if is_partition dev then Mountable.of_device dev
    else default
  )
