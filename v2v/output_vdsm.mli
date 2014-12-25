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

(** [-o vdsm] target. *)

type vdsm_params = {
  image_uuids : string list;          (* --vdsm-image-uuid (multiple) *)
  vol_uuids : string list;            (* --vdsm-vol-uuid (multiple) *)
  vm_uuid : string;                   (* --vdsm-vm-uuid *)
  ovf_output : string;                (* --vdsm-ovf-output *)
}
(** Miscellaneous extra command line parameters used by VDSM. *)

val output_vdsm : bool -> string -> vdsm_params -> [`Server|`Desktop] option -> [`Sparse|`Preallocated] -> Types.output
(** [output_vdsm verbose os rhev_params output_alloc] creates and
    returns a new {!Types.output} object specialized for writing
    output to Data Domains directly under VDSM control. *)
