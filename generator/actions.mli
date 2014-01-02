(* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(* Please read generator/README first. *)

(** The libguestfs API. *)

val non_daemon_functions : Types.action list
(** API actions which are implemented within the library itself. *)

val daemon_functions : Types.action list
(** API actions which are implemented by the daemon. *)

val all_functions : Types.action list
(** Concatenation of [non_daemon_functions] and [daemon_functions] lists. *)

val is_external : Types.action -> bool
(** Returns true if function is external, false otherwise *)

val is_internal : Types.action -> bool
(** Returns true if function is internal, false otherwise *)

val is_documented : Types.action -> bool
(** Returns true if function should be documented, false otherwise *)

val is_fish : Types.action -> bool
(** Returns true if function should be in guestfish, false otherwise *)

val external_functions : Types.action list
(** [all_functions] filtered for external functions **)

val internal_functions : Types.action list
(** [all_functions] filtered for internal functions **)

val documented_functions : Types.action list
(** [all_functions] filtered for functions requiring documentation **)

val fish_functions : Types.action list
(** [all_functions] filtered for functions in guestfish **)

val all_functions_sorted : Types.action list
(** [all_functions] but sorted by name. *)

val external_functions_sorted : Types.action list
(** [external_functions] but sorted by name. *)

val internal_functions_sorted : Types.action list
(** [internal_functions] but sorted by name. *)

val documented_functions_sorted : Types.action list
(** [documented_functions] but sorted by name. *)

val fish_functions_sorted : Types.action list
(** [fish_functions] but sorted by name. *)

val test_functions : Types.action list
(** Internal test functions used to test the language bindings. *)

val max_proc_nr : int
(** The largest procedure number used (also saved in [src/MAX_PROC_NR] and
    used as the minor version number of the shared library). *)

val fish_commands : Types.action list
(** Non-API meta-commands available only in guestfish. *)
