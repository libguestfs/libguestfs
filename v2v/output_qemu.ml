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

class output_qemu verbose dir qemu_boot =
object
  inherit output verbose

  method as_options =
    sprintf "-o qemu -os %s%s" dir (if qemu_boot then " --qemu-boot" else "")

  method prepare_targets source targets =
    List.map (
      fun t ->
        let target_file = dir // source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method create_metadata source targets guestcaps _ =
    let name = source.s_name in
    let file = dir // name ^ ".sh" in

    let chan = open_out file in

    let fpf fs = fprintf chan fs in
    fpf "#!/bin/sh -\n";
    fpf "\n";
    fpf "qemu-system-%s \\\n" guestcaps.gcaps_arch;
    fpf "\t-no-user-config -nodefaults \\\n";
    fpf "\t-name %s \\\n" (quote source.s_name);
    fpf "\t-machine accel=kvm:tcg \\\n";
    fpf "\t-m %Ld \\\n" (source.s_memory /^ 1024L /^ 1024L);
    if source.s_vcpu > 1 then
      fpf "\t-smp %d \\\n" source.s_vcpu;

    let block_bus =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk -> "virtio"
      | IDE -> "ide" in
    List.iter (
      fun t ->
        let qemu_quoted_filename = replace_str t.target_file "," ",," in
        let drive_param =
          sprintf "file=%s,format=%s,if=%s"
            qemu_quoted_filename t.target_format block_bus in
        fpf "\t-drive %s\\\n" (quote drive_param)
    ) targets;

    let net_bus =
      match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio-net-pci"
      | E1000 -> "e1000"
      | RTL8139 -> "rtl8139" in
    List.iteri (
      fun i nic ->
        fpf "\t-netdev user,id=net%d \\\n" i;
        fpf "\t-device %s,netdev=net%d%s \\\n"
          net_bus i (match nic.s_mac with None -> "" | Some mac -> ",mac=" ^ mac)
    ) source.s_nics;

    (* Add a serial console. *)
    fpf "\t-serial stdio\n";

    (* XXX Missing:
     * - removable devices
     * - display
     *)

    close_out chan;

    Unix.chmod file 0o755;

    (* If --qemu-boot option was specified then we should boot the guest. *)
    if qemu_boot then (
      let cmd = sprintf "%s &" (quote file) in
      ignore (Sys.command cmd)
    )
end

let output_qemu = new output_qemu
let () = Modules_list.register_output_module "qemu"
