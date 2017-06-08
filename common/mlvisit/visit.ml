(* Bindings for visitor function.
 * Copyright (C) 2016 Red Hat Inc.
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

type visitor_function = string -> string option -> Guestfs.statns -> Guestfs.xattr array -> unit

external c_visit : int64 -> string -> visitor_function -> unit =
  "guestfs_int_mllib_visit"

let visit g dir f =
  c_visit (Guestfs.c_pointer g) dir f

external full_path : string -> string option -> string =
  "guestfs_int_mllib_full_path"

external is_reg : int64 -> bool = "guestfs_int_mllib_is_reg" "noalloc"
external is_dir : int64 -> bool = "guestfs_int_mllib_is_dir" "noalloc"
external is_chr : int64 -> bool = "guestfs_int_mllib_is_chr" "noalloc"
external is_blk : int64 -> bool = "guestfs_int_mllib_is_blk" "noalloc"
external is_fifo : int64 -> bool = "guestfs_int_mllib_is_fifo" "noalloc"
external is_lnk : int64 -> bool = "guestfs_int_mllib_is_lnk" "noalloc"
external is_sock : int64 -> bool = "guestfs_int_mllib_is_sock" "noalloc"
