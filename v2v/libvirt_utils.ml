(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(* This module implements various [virsh]-like commands, but with
    non-broken authentication handling. *)

external dumpxml : ?password:string -> ?conn:string -> string -> string = "v2v_dumpxml"
let dumpxml ?password_file =
  let password = Option.map read_first_line_from_file password_file in
  dumpxml ?password

external pool_dumpxml : ?conn:string -> string -> string = "v2v_pool_dumpxml"
external vol_dumpxml : ?conn:string -> string -> string -> string = "v2v_vol_dumpxml"

external capabilities : ?conn:string -> unit -> string = "v2v_capabilities"

external domain_exists : ?conn:string -> string -> bool = "v2v_domain_exists"

external libvirt_get_version : unit -> int * int * int
  = "v2v_libvirt_get_version"
