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

let initialize dir source overlays =
  List.map (
    fun ov ->
      let target_file = dir // source.s_name ^ "-" ^ ov.ov_sd in
      { ov with ov_target_file = target_file }
  ) overlays

let create_metadata dir source overlays guestcaps =
  let name = source.s_name in
  let file = dir // name ^ ".xml" in

  let chan = open_out file in
  let p fs = fprintf chan fs in

  p "<domain type='%s'>\n" "kvm"; (* Always assume target is kvm? *)
  p "  <name>%s</name>\n" name;
  let memory_k = source.s_memory /^ 1024L in
  p "  <memory unit='KiB'>%Ld</memory>\n" memory_k;
  p "  <currentMemory unit='KiB'>%Ld</currentMemory>\n" memory_k;
  p "  <vcpu>%d</vcpu>\n" source.s_vcpu;
  p "  <os>\n";
  p "    <type arch='%s'>hvm</type>\n" source.s_arch;
  p "  </os>\n";
  p "  <features>\n";
  List.iter (p "    <%s/>\n") source.s_features;
  p "  </features>\n";

  p "  <on_poweroff>destroy</on_poweroff>\n";
  p "  <on_reboot>restart</on_reboot>\n";
  p "  <on_crash>restart</on_crash>\n";
  p "  <devices>\n";

  let block_prefix =
    if guestcaps.gcaps_block_bus = "virtio" then "vd" else "hd" in
  iteri (
    fun i ov ->
      p "    <disk type='file' device='disk'>\n";
      p "      <driver name='qemu' type='%s' cache='none'/>\n"
        ov.ov_target_format;
      p "      <source file='%s'/>\n" (xml_quote_attr ov.ov_target_file);
      p "      <target dev='%s%s' bus='%s'/>\n"
        block_prefix (drive_name i) guestcaps.gcaps_block_bus;
      p "    </disk>\n";
  ) overlays;

  p "    <input type='tablet' bus='usb'/>\n";
  p "    <input type='mouse' bus='ps2'/>\n";
  p "    <console type='pty'/>\n";

  (* XXX Missing here from old virt-v2v:
     <video/>
     <graphics/>
     cdroms and floppies
     network interfaces
     See: lib/Sys/VirtConvert/Connection/LibVirtTarget.pm
  *)

  p "</domain>\n";

  close_out chan
