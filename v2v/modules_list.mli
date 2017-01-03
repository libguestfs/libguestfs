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

(** List of input, output and conversion modules. *)

val register_input_module : string -> unit
(** Register an input module by name. *)

val register_output_module : string -> unit
(** Register an output module by name. *)

val input_modules : unit -> string list
(** Return the list of input modules. *)

val output_modules : unit -> string list
(** Return the list of output modules. *)

type inspection_fn = Types.inspect -> bool

type conversion_fn =
  Guestfs.guestfs -> Types.inspect -> Types.source -> Types.output_settings ->
  Types.requested_guestcaps -> Types.guestcaps

val register_convert_module : inspection_fn -> string -> conversion_fn -> unit
(** [register_convert_module inspect_fn name fn] registers a
    conversion function [fn] that can accept any guest that matches
    the [inspect_fn] function. *)

val find_convert_module : Types.inspect -> string * conversion_fn
(** [find_convert_module inspect] returns the name and conversion
    function for the guest with inspection data in [inspect], else
    throws [Not_found]. *)

val convert_modules : unit -> string list
(** Return the list of conversion modules. *)
