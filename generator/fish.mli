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

val generate_fish_actions_pod : unit -> unit
val generate_fish_run_cmds : Types.action list -> unit -> unit
val generate_fish_run_header : unit -> unit
val generate_fish_cmd_entries : Types.action list -> unit -> unit
val generate_fish_cmds : unit -> unit
val generate_fish_cmds_gperf : unit -> unit
val generate_fish_cmds_h : unit -> unit
val generate_fish_commands_pod : unit -> unit
val generate_fish_completion : unit -> unit
val generate_fish_event_names : unit -> unit
val generate_fish_prep_options_c : unit -> unit
val generate_fish_prep_options_h : unit -> unit
val generate_fish_prep_options_pod : unit -> unit
val generate_fish_test_prep_sh : unit -> unit
