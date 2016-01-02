(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

(** [-o rhev] target. *)

val mount_and_check_storage_domain : string -> string -> (string * string)
(** This helper function is also used by the VDSM target. *)

val output_rhev : string -> Types.vmtype option -> Types.output_allocation -> Types.output
(** [output_rhev os vmtype output_alloc] creates and
    returns a new {!Types.output} object specialized for writing
    output to RHEV-M or oVirt Export Storage Domain. *)
