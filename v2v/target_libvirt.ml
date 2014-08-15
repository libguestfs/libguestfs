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
open DOM

let create_libvirt_xml source overlays guestcaps =
  let memory_k = source.s_memory /^ 1024L in

  let features =
    List.filter (
      fun feature ->
        (* drop acpi if the guest doesn't support it *)
        feature <> "acpi" || guestcaps.gcaps_acpi
    ) source.s_features in


  let disks =
    let block_prefix =
      if guestcaps.gcaps_block_bus = "virtio" then "vd" else "hd" in
    List.mapi (
      fun i ov ->
        e "disk" ["type", "file"; "device", "disk"] [
          e "driver" [
            "name", "qemu";
            "type", ov.ov_target_format;
            "cache", "none"
          ] [];
          e "source" [
            "file", ov.ov_target_file;
          ] [];
          e "target" [
            "dev", block_prefix ^ (drive_name i);
            "bus", guestcaps.gcaps_block_bus;
          ] [];
        ]
    ) overlays in

  (* XXX Missing here from list of devices compared to old virt-v2v:
     <video/>
     <graphics/>
     cdroms and floppies
     network interfaces
     See: lib/Sys/VirtConvert/Connection/LibVirtTarget.pm
  *)
  let devices = disks @
  (* Standard devices added to every guest. *) [
    e "input" ["type", "tablet"; "bus", "usb"] [];
    e "input" ["type", "mouse"; "bus", "ps2"] [];
    e "console" ["type", "pty"] [];
  ] in

  let doc : doc =
    doc "domain" [
      "type", "kvm";                (* Always assume target is kvm? *)
    ] [
      e "name" [] [PCData source.s_name];
      e "memory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "currentMemory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "vcpu" [] [PCData (string_of_int source.s_vcpu)];
      e "os" [] [
        e "type" ["arch", source.s_arch] [PCData "hvm"];
      ];
      e "features" [] (List.map (fun s -> PCData s) features);

      e "on_poweroff" [] [PCData "destroy"];
      e "on_reboot" [] [PCData "restart"];
      e "on_crash" [] [PCData "restart"];

      e "devices" [] devices;
    ] (* /doc *) in

  doc
