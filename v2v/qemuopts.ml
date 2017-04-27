(* virt-v2v
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

type t

external create : unit -> t = "guestfs_int_qemuopts_create"
external set_binary : t -> string -> unit = "guestfs_int_qemuopts_set_binary"
external set_binary_by_arch : t -> string option -> unit = "guestfs_int_qemuopts_set_binary_by_arch"
external flag : t -> string -> unit = "guestfs_int_qemuopts_flag"
external arg : t -> string -> string -> unit = "guestfs_int_qemuopts_arg"
external arg_noquote : t -> string -> string -> unit = "guestfs_int_qemuopts_arg_noquote"
external arg_list : t -> string -> string list -> unit = "guestfs_int_qemuopts_arg_list"
external to_script : t -> string -> unit = "guestfs_int_qemuopts_to_script"

external _to_chan : t -> Unix.file_descr -> unit = "guestfs_int_qemuopts_to_chan"

let to_chan t chan =
  flush chan;
  let fd = Unix.descr_of_out_channel chan in
  _to_chan t fd
