(* guestfs-inspection
 * Copyright (C) 2009-2025 Red Hat Inc.
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
open Scanf

open Std_utils

open Utils

(* The output is horrific ...

meta-data=/dev/sda1              isize=512    agcount=4, agsize=122094659 blks
         =                       sectsz=4096  attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1    bigtime=1 inobtcount=1 nrext64=0
         =                       exchange=0   metadir=0
data     =                       bsize=4096   blocks=488378636, imaxpct=5
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1, parent=0
log      =internal log           bsize=4096   blocks=238466, version=2
         =                       sectsz=4096  sunit=1 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
         =                       rgcount=0    rgsize=0 extents
         =                       zoned=0      start=0 reserved=0

^heading  ^"stuff"               ^ data fields vaguely related to heading

Note also the inconsistent use of commas.
*)

(* Split into groups using a positive lookahead assertion. *)
let re1 = PCRE.compile ~extended:true {| \n (?=[a-z]) |}

(* Separate group heading and the rest. *)
let re2 = PCRE.compile ~extended:true {| = |}

(* Match the first field in a group (if present). *)
let re3 = PCRE.compile ~anchored:true ~extended:true {|
   (version\s\d+|\S+\slog|\S+).*
|}

(* Match next field=value in group. *)
let re4 = PCRE.compile ~extended:true {|
   ([-\w]+)=(\d+(\s(blks|extents))?)
|}

let xfs_info2 dev =
  (* Uncomment the first line to enable extra debugging. *)
  (*let extra_debug = verbose () in*)
  let extra_debug = false in

  let is_dev = is_device_parameter dev in
  let arg = if is_dev then dev else Sysroot.sysroot_path dev in
  let out = command "xfs_info" [arg] in

  (* Split the output by heading. *)
  let groups = PCRE.nsplit re1 out in
  let groups = List.map (PCRE.split re2) groups in
  let groups = List.map (fun (name, rest) -> String.trim name, rest) groups in

  if extra_debug then (
    List.iteri (
      fun i (name, rest) ->
        eprintf "xfs_info2: group %d: %S: %S\n%!" i name rest
    ) groups
  );

  (* Parse each group into the final list of values. *)
  let values = ref [] in
  List.iter (
    fun (group_name, rest) ->
      let len = String.length rest in

      (* If there is some string at the beginning of the
       * group then we create a (group_name, string) value,
       * eg. ("meta-data", "/dev/sda1")
       *)
      let start =
        if PCRE.matches re3 rest then (
          let value = PCRE.sub 1 in
          List.push_front (group_name, value) values;
          (* Start parsing after this. *)
          String.length value
        )
        else 0 in

      let rec loop i =
        if extra_debug then
          eprintf "xfs_info2: parsing group %S from %d\n%!" group_name i;
        if i <= len && PCRE.matches ~offset:i re4 rest then (
          let field_name = PCRE.sub 1 in
          if extra_debug then eprintf "xfs_info2: sub1=%S\n%!" field_name;
          let value = PCRE.sub 2 in
          if extra_debug then eprintf "xfs_info2: sub2=%S\n%!" value;
          let name = sprintf "%s.%s" group_name field_name in
          List.push_front (name, value) values;

          (* Next time round the loop, start parsing after the
           * current matched subexpression.
           *)
          loop (snd (PCRE.subi 2) + 1)
        )
      in
      (try
         loop start
       with
         Not_found ->
         failwithf "xfs_info2: internal error: unexpected Not_found exception. Enable debug and send the full output in a bug report."
      );

  ) groups;

  List.rev !values

(* Deprecated xfs_info. *)
let xfs_info dev =
  let h = xfs_info2 dev in

  let find field parsefn =
    try List.assoc field h |> parsefn
    with
    | Not_found ->
       failwithf "xfs_info: unexpected missing field: %s" field
    | exn ->
       failwithf "xfs_info: failure finding field: %s: %s"
         field (Printexc.to_string exn)
  in

  let parse_blks s = sscanf s "%ld blks" Fun.id in
  let parse_version s = sscanf s "version %ld" Fun.id in

  { Structs.xfs_mntpoint = find "meta-data"      Fun.id;
    xfs_inodesize    = find "meta-data.isize"    Int32.of_string;
    xfs_agcount      = find "meta-data.agcount"  Int32.of_string;
    xfs_agsize       = find "meta-data.agsize"   parse_blks;
    xfs_sectsize     = find "meta-data.sectsz"   Int32.of_string;
    xfs_attr         = find "meta-data.attr"     Int32.of_string;
    xfs_blocksize    = find "data.bsize"         Int32.of_string;
    xfs_datablocks   = find "data.blocks"        Int64.of_string;
    xfs_imaxpct      = find "data.imaxpct"       Int32.of_string;
    xfs_sunit        = find "data.sunit"         Int32.of_string;
    xfs_swidth       = find "data.swidth"        parse_blks;
    xfs_dirversion   = find "naming"             parse_version;
    xfs_dirblocksize = find "naming.bsize"       Int32.of_string;
    xfs_cimode       = find "naming.ascii-ci"    Int32.of_string;
    xfs_logname      = find "log"                Fun.id;
    xfs_logblocksize = find "log.bsize"          Int32.of_string;
    xfs_logblocks    = find "log.blocks"         Int32.of_string;
    xfs_logversion   = find "log.version"        Int32.of_string;
    xfs_logsectsize  = find "log.sectsz"         Int32.of_string;
    xfs_logsunit     = find "log.sunit"          parse_blks;
    xfs_lazycount    = find "log.lazy-count"     Int32.of_string;
    xfs_rtname       = find "realtime"           Fun.id;
    xfs_rtextsize    = find "realtime.extsz"     Int32.of_string;
    xfs_rtblocks     = find "realtime.blocks"    Int64.of_string;
    xfs_rtextents    = find "realtime.rtextents" Int64.of_string;
  }

let maxmem_re =
  PCRE.compile ~anchored:false ~dotall:true
    {|Required memory for repair is greater tha. the maximum specified.*at least (\d+)\.|}

let bad_agbno_in_agfl_re =
  PCRE.compile ~anchored:false {|bad agbno \d+ in agfl, agno \d+|}

let xfs_repair
      ?(forcelogzero = false)
      ?(nomodify = false)
      ?(noprefetch = false)
      ?(forcegeometry = false)
      ?maxmem ?ihashsize ?bhashsize ?agstride ?logdev ?rtdev device =
  let args = ref [] in
  if forcelogzero then List.push_back args "-L";
  if nomodify then List.push_back args "-n";
  if noprefetch then List.push_back args "-P";
  if forcegeometry then List.push_back_list args [ "-o"; "force_geometry" ];
  (match maxmem with
   | None -> ()
   | Some m when m < 0_L -> invalid_arg "maxmem must be >= 0"
   | Some m ->
      List.push_back_list args [ "-m"; Int64.to_string m ]
  );
  (match ihashsize with
   | None -> ()
   | Some i when i < 0_L -> invalid_arg "ihashsize must be >= 0"
   | Some i ->
      List.push_back_list args [ "-o"; sprintf "ihash=%Ld" i ]
  );
  (match bhashsize with
   | None -> ()
   | Some i when i < 0_L -> invalid_arg "bhashsize must be >= 0"
   | Some i ->
      List.push_back_list args [ "-o"; sprintf "bhash=%Ld" i ]
  );
  (match agstride with
   | None -> ()
   | Some i when i < 0_L -> invalid_arg "agstride must be >= 0"
   | Some i ->
      List.push_back_list args [ "-o"; sprintf "ag_stride=%Ld" i ]
  );
  (match logdev with
   | None -> ()
   | Some d -> List.push_back_list args [ "-l"; d ]
  );
  (match rtdev with
   | None -> ()
   | Some d -> List.push_back_list args [ "-r"; d ]
  );

  if is_device_parameter device then (
    List.push_back args device
  )
  else (
    (* It's a filesystem image stored in the mounted filesystem.
     * This slightly dubious usage has been present since the
     * API was first added to libguestfs back in 2012 (commit 7036a3bccf).
     *)
    List.push_back args "-f";
    List.push_back args (Sysroot.sysroot_path device)
  );

  (* Run the xfs_repair command, returning the status directly. *)
  let r, _, err = commandr "xfs_repair" !args in

  (* If the error indicates that -m was too small, turn that into
   * an error exception (RHEL-165677).
   *)
  if PCRE.matches maxmem_re err then (
    let old_maxmem =
      Option.map Int64.to_string maxmem |>
      Option.value ~default:"(not set)" in
    let new_maxmem = PCRE.sub 1 in
    let msg = sprintf "maxmem parameter (-m option) was too small: raise it from %s to at least %s" old_maxmem new_maxmem in
    invalid_arg msg
  );

  (* RHEL 7 XFS had a bug in on-disk AGFL (free list) structs.  This
   * was fixed later (linux kernel commit 96f859d).  But the RHEL 7
   * kernel was patched to detect this case and do a fix up.  Later
   * xfs_repair (eg RHEL 10) flags the RHEL 7 structs as an error,
   * incorrectly.  Detect this case and ignore the error. (RHEL-178287)
   *)
  let r =
    if r = 1 && PCRE.matches bad_agbno_in_agfl_re err then (
      eprintf "xfs_repair: \
               ignoring RHEL 7 AGFL inconsistency (RHEL-178287)\n%!";
      0
    )
    else r in

  r
