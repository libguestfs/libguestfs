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
open Unix

open Std_utils

open Utils

let rec findfs_uuid uuid =
  findfs "UUID" uuid
and findfs_label label =
  findfs "LABEL"label

and findfs tag str =
  (* Kill the cache file, forcing blkid to reread values from the
   * original filesystems.  In blkid there is a '-p' option which is
   * supposed to do this, but (a) it doesn't work and (b) that option
   * is not supported in RHEL 5.
   *)
  (try unlink "/etc/blkid/blkid.tab" with Unix_error _ -> ());
  (try unlink "/run/blkid/blkid.tab" with Unix_error _ -> ());

  let out = command "findfs" [ sprintf "%s=%s" tag str ] in

  (* Trim trailing \n if present. *)
  let out = String.trim out in

  if String.is_prefix out "/dev/mapper/" ||
     String.is_prefix out "/dev/dm-" then (
    match Lvm_utils.lv_canonical out with
    | None ->
       (* Ignore the case where 'out' doesn't appear to be an LV.
        * The best we can do is return the original as-is.
        *)
       out
    | Some out -> out
  )
  else
    out
