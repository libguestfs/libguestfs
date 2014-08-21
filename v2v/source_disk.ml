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

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

let create input_format disk =
  (* What name should we use for the guest?  We try to derive it from
   * the filename passed in.  Users can override this using the
   * `-on name' option.
   *)
  let name = Filename.chop_extension (Filename.basename disk) in
  if name = "" then
    error (f_"-i disk: invalid input filename (%s)") disk;

  (* Get the absolute path to the disk file. *)
  let disk_absolute =
    if not (Filename.is_relative disk) then disk
    else Sys.getcwd () // disk in

  (* The rest of virt-v2v doesn't actually work unless we detect
   * the format of the input, so:
   *)
  let format =
    match input_format with
    | Some format -> format
    | None ->
      match (new Guestfs.guestfs ())#disk_format disk with
      | "unknown" ->
        error (f_"cannot detect the input disk format; use the -if parameter")
      | format -> format in

  let disk = {
    s_qemu_uri = disk_absolute;
    s_format = Some format;
    s_target_dev = None;
  } in

  (* Give the guest a simple generic network interface. *)
  let network = {
    s_mac = None;
    s_vnet = "default";
    s_vnet_type = `Network
  } in

  let source = {
    s_dom_type = "kvm";
    s_name = name; s_orig_name = name;
    s_memory = 2048L *^ 1024L *^ 1024L; (* 2048 MB *)
    s_vcpu = 1;                         (* 1 vCPU is a safe default *)
    s_arch = Config.host_cpu;
    s_features = [ "acpi"; "apic"; "pae" ];
    s_display = None;
    s_disks = [disk];
    s_removables = [];
    s_nics = [ network ];
  } in

  source
