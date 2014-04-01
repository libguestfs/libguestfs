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

open Printf

(* Types.  See types.mli for documentation. *)

type input =
| InputLibvirt of string option * string
| InputLibvirtXML of string

type output =
| OutputLibvirt of string option
| OutputLocal of string
| OutputRHEV of string

type source = {
  s_dom_type : string;
  s_name : string;
  s_memory : int64;
  s_vcpu : int;
  s_arch : string;
  s_features : string list;
  s_disks : source_disk list;
}
and source_disk = string * string option

type overlay = {
  ov_overlay : string;
  ov_target_file : string;
  ov_target_file_tmp : string;
  ov_target_format : string;
  ov_sd : string;
  ov_virtual_size : int64;
  ov_preallocation : string option;
  ov_source_file : string;
  ov_source_format : string option;
}

let string_of_overlay ov =
  sprintf "\
ov_overlay = %s
ov_target_file = %s
ov_target_file_tmp = %s
ov_target_format = %s
ov_sd = %s
ov_virtual_size = %Ld
ov_preallocation = %s
ov_source_file = %s
ov_source_format = %s
"
    ov.ov_overlay
    ov.ov_target_file ov.ov_target_file_tmp
    ov.ov_target_format
    ov.ov_sd
    ov.ov_virtual_size
    (match ov.ov_preallocation with None -> "None" | Some s -> s)
    ov.ov_source_file
    (match ov.ov_source_format with None -> "None" | Some s -> s)

type inspect = {
  i_root : string;
  i_apps : Guestfs.application2 list;
}

type guestcaps = {
  gcaps_block_bus : string;
  gcaps_net_bus : string;
}
