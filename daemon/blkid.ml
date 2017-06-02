(* guestfs-inspection
 * Copyright (C) 2009-2017 Red Hat Inc.
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

open Std_utils

open Utils

let rec vfs_type { Mountable.m_device = device } =
  get_blkid_tag device "TYPE"

and get_blkid_tag device tag =
  let r, out, err =
    commandr "blkid"
             [(* Adding -c option kills all caching, even on RHEL 5. *)
               "-c"; "/dev/null";
               "-o"; "value"; "-s"; tag; device] in
  match r with
  | 0 ->                        (* success *)
     String.chomp out

  | 2 ->                        (* means tag not found, we return "" *)
     ""

  | _ ->
     failwithf "blkid: %s: %s: %s" device tag err
