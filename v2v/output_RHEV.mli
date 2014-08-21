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

(** [-o rhev] target. *)

type rhev_params = {
  image_uuid : string option;           (* --rhev-image-uuid *)
  vol_uuids : string list;              (* --rhev-vol-uuid (multiple) *)
  vm_uuid : string option;              (* --rhev-vm-uuid *)
  vmtype : [`Server|`Desktop] option;   (* --vmtype *)
}
(** Miscellaneous extra command line parameters used by RHEV. *)

val output_rhev : bool -> string -> rhev_params -> [`Sparse|`Preallocated] -> Types.output
(** [output_rhev verbose os rhev_params output_alloc] creates and
    returns a new {!Types.output} object specialized for writing
    output to RHEV-M or oVirt. *)
