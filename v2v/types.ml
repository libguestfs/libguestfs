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
| InputDisk of string option * string
| InputLibvirt of string option * string
| InputLibvirtXML of string

type output =
| OutputLibvirt of string option * string
| OutputLocal of string
| OutputRHEV of string * output_rhev_params

and output_rhev_params = {
  image_uuid : string option;
  vol_uuids : string list;
  vm_uuid : string option;
  vmtype : [`Server|`Desktop] option;
}

let output_as_options = function
  | OutputLibvirt (None, os) ->
    sprintf "-o libvirt -os %s" os
  | OutputLibvirt (Some uri, os) ->
    sprintf "-o libvirt -oc %s -os %s" uri os
  | OutputLocal os ->
    sprintf "-o local -os %s" os
  | OutputRHEV (os, params) ->
    sprintf "-o rhev -os %s%s%s%s%s" os
      (match params.image_uuid with
      | None -> "" | Some uuid -> sprintf " --rhev-image-uuid %s" uuid)
      (String.concat ""
         (List.map (sprintf " --rhev-vol-uuid %s") params.vol_uuids))
      (match params.vm_uuid with
      | None -> "" | Some uuid -> sprintf " --rhev-vm-uuid %s" uuid)
      (match params.vmtype with
      | None -> ""
      | Some `Server -> " --vmtype server"
      | Some `Desktop -> " --vmtype desktop")

type source = {
  s_dom_type : string;
  s_name : string;
  s_orig_name : string;
  s_memory : int64;
  s_vcpu : int;
  s_arch : string;
  s_features : string list;
  s_display : source_display option;
  s_disks : source_disk list;
  s_removables : source_removable list;
  s_nics : source_nic list;
}
and source_disk = {
  s_qemu_uri : string;
  s_format : string option;
  s_target_dev : string option;
}
and source_removable = {
  s_removable_type : [`CDROM|`Floppy];
  s_removable_target_dev : string option;
}
and source_nic = {
  s_mac : string option;
  s_vnet : string;
  s_vnet_type : [`Bridge|`Network];
}
and source_display = {
  s_display_type : [`VNC|`Spice];
  s_keymap : string option;
  s_password : string option;
}

let rec string_of_source s =
  sprintf "\
s_dom_type = %s
s_name = %s
s_memory = %Ld
s_vcpu = %d
s_arch = %s
s_features = [%s]
s_display = %s
s_disks = [%s]
s_removables = [%s]
s_nics = [%s]
"
    s.s_dom_type
    s.s_name
    s.s_memory
    s.s_vcpu
    s.s_arch
    (String.concat "," s.s_features)
    (match s.s_display with
    | None -> ""
    | Some display -> string_of_source_display display)
    (String.concat "," (List.map string_of_source_disk s.s_disks))
    (String.concat "," (List.map string_of_source_removable s.s_removables))
    (String.concat "," (List.map string_of_source_nic s.s_nics))

and string_of_source_disk { s_qemu_uri = qemu_uri; s_format = format;
                            s_target_dev = target_dev } =
  sprintf "%s%s%s"
    qemu_uri
    (match format with
    | None -> ""
    | Some format -> " (" ^ format ^ ")")
    (match target_dev with
    | None -> ""
    | Some target_dev -> " [" ^ target_dev ^ "]")

and string_of_source_removable { s_removable_type = typ;
                                 s_removable_target_dev = target_dev } =
  sprintf "%s%s"
    (match typ with `CDROM -> "cdrom" | `Floppy -> "floppy")
    (match target_dev with
    | None -> ""
    | Some target_dev -> " [" ^ target_dev ^ "]")

and string_of_source_nic { s_mac = mac; s_vnet = vnet; s_vnet_type = typ } =
  sprintf "%s%s%s"
    (match typ with `Bridge -> "bridge" | `Network -> "network")
    vnet
    (match mac with
    | None -> ""
    | Some mac -> " " ^ mac)

and string_of_source_display { s_display_type = typ;
                               s_keymap = keymap; s_password = password } =
  sprintf "%s%s%s"
    (match typ with `VNC -> "vnc" | `Spice -> "spice")
    (match keymap with None -> "" | Some km -> " " ^ km)
    (match password with None -> "" | Some _ -> " with password")

type overlay = {
  ov_overlay : string;
  ov_target_file : string;
  ov_target_format : string;
  ov_sd : string;
  ov_virtual_size : int64;
  ov_preallocation : string option;
  ov_source_file : string;
  ov_source_format : string option;
  ov_vol_uuid : string;
}

let string_of_overlay ov =
  sprintf "\
ov_overlay = %s
ov_target_file = %s
ov_target_format = %s
ov_sd = %s
ov_virtual_size = %Ld
ov_preallocation = %s
ov_source_file = %s
ov_source_format = %s
ov_vol_uuid = %s
"
    ov.ov_overlay
    ov.ov_target_file
    ov.ov_target_format
    ov.ov_sd
    ov.ov_virtual_size
    (match ov.ov_preallocation with None -> "None" | Some s -> s)
    ov.ov_source_file
    (match ov.ov_source_format with None -> "None" | Some s -> s)
    ov.ov_vol_uuid

type inspect = {
  i_root : string;
  i_type : string;
  i_distro : string;
  i_arch : string;
  i_major_version : int;
  i_minor_version : int;
  i_package_format : string;
  i_package_management : string;
  i_product_name : string;
  i_product_variant : string;
  i_apps : Guestfs.application2 list;
  i_apps_map : Guestfs.application2 list StringMap.t;
}

type guestcaps = {
  gcaps_block_bus : string;
  gcaps_net_bus : string;
  gcaps_acpi : bool;
  gcaps_video : string;
}
