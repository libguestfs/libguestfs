(* virt-sparsify
 * Copyright (C) 2011-2018 Red Hat Inc.
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

(** This is the traditional virt-sparsify mode: We copy from a
    source disk to a destination disk. *)

type tmp_place =
| Directory of string | Block_device of string | Prebuilt_file of string

val run : string -> string -> Cmdline.check_t -> bool -> string option -> string option -> string list -> string option -> string option -> string list -> Tools_utils.key_store -> unit
