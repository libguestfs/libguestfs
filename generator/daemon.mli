(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

val generate_daemon_actions_h : unit -> unit
val generate_daemon_stubs_h : unit -> unit
val generate_daemon_stubs : Types.action list -> unit -> unit
val generate_daemon_caml_stubs : unit -> unit
val generate_daemon_caml_callbacks_ml : unit -> unit
val generate_daemon_caml_interface : string -> unit -> unit
val generate_daemon_dispatch : unit -> unit
val generate_daemon_lvm_tokenization : unit -> unit
val generate_daemon_names : unit -> unit
val generate_daemon_optgroups_c : unit -> unit
val generate_daemon_optgroups_h : unit -> unit
val generate_daemon_optgroups_ml : unit -> unit
val generate_daemon_optgroups_mli : unit -> unit
val generate_daemon_structs_cleanups_c : unit -> unit
val generate_daemon_structs_cleanups_h : unit -> unit
