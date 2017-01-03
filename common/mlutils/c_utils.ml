(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

(* OCaml bindings for C utility functions in [common/utils]. *)

open Printf

external drive_name : int -> string = "guestfs_int_mlutils_drive_name"
external drive_index : string -> int = "guestfs_int_mlutils_drive_index"

external shell_unquote : string -> string = "guestfs_int_mlutils_shell_unquote"

external is_reg : int64 -> bool = "guestfs_int_mlutils_is_reg" "noalloc"
external is_dir : int64 -> bool = "guestfs_int_mlutils_is_dir" "noalloc"
external is_chr : int64 -> bool = "guestfs_int_mlutils_is_chr" "noalloc"
external is_blk : int64 -> bool = "guestfs_int_mlutils_is_blk" "noalloc"
external is_fifo : int64 -> bool = "guestfs_int_mlutils_is_fifo" "noalloc"
external is_lnk : int64 -> bool = "guestfs_int_mlutils_is_lnk" "noalloc"
external is_sock : int64 -> bool = "guestfs_int_mlutils_is_sock" "noalloc"

external full_path : string -> string option -> string = "guestfs_int_mlutils_full_path"
