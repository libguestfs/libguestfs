(* virt-v2v
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(** [-i libvirt] source. *)

val error_if_libvirt_backend : unit -> unit
val error_if_no_ssh_agent : unit -> unit

class virtual input_libvirt : bool -> string option -> string option -> string -> object
  method as_options : string
  method virtual source : unit -> Types.source
  method adjust_overlay_parameters : Types.overlay -> unit
end

val input_libvirt_other : bool -> string option -> string option -> string -> Types.input
