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

type optarg_proto = Dots | VA | Argv

val generate_prototype : ?extern:bool -> ?static:bool -> ?semicolon:bool -> ?single_line:bool -> ?indent:string -> ?newline:bool -> ?in_daemon:bool -> ?dll_public:bool -> ?attribute_noreturn:bool -> ?prefix:string -> ?suffix:string -> ?handle:string -> ?optarg_proto:optarg_proto -> string -> Types.style -> unit

val generate_c_call_args : ?handle:string -> ?implicit_size_ptr:string -> ?in_daemon:bool -> Types.ret * Types.args * Types.optargs -> unit

val generate_actions_pod : unit -> unit
val generate_availability_pod : unit -> unit
val generate_client_actions : Types.action list -> unit -> unit
val generate_client_actions_variants : unit -> unit
val generate_client_structs_cleanups_h : unit -> unit
val generate_client_structs_cleanups_c : unit -> unit
val generate_client_structs_compare : unit -> unit
val generate_client_structs_copy : unit -> unit
val generate_client_structs_free : unit -> unit
val generate_client_structs_print_h : unit -> unit
val generate_client_structs_print_c : unit -> unit
val generate_event_string_c : unit -> unit
val generate_guestfs_h : unit -> unit
val generate_internal_actions_h : unit -> unit
val generate_linker_script : unit -> unit
val generate_max_proc_nr : unit -> unit
val generate_structs_pod : unit -> unit
