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

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

class output_qemu dir qemu_boot =
object
  inherit output

  method as_options =
    sprintf "-o qemu -os %s%s" dir (if qemu_boot then " --qemu-boot" else "")

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    List.map (
      fun t ->
        let target_file = dir // source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method check_target_firmware guestcaps target_firmware =
    match target_firmware with
    | TargetBIOS -> ()
    | TargetUEFI ->
       (* This will fail with an error if the target firmware is
        * not installed on the host.
        *)
       ignore (find_uefi_firmware guestcaps.gcaps_arch)

  method create_metadata source _ target_buses guestcaps inspect
                         target_firmware =
    let name = source.s_name in
    let file = dir // name ^ ".sh" in

    let uefi_firmware =
      match target_firmware with
      | TargetBIOS -> None
      | TargetUEFI ->
         Some (find_uefi_firmware guestcaps.gcaps_arch) in

    let chan = open_out file in

    let fpf fs = fprintf chan fs in
    let nl = " \\\n\t" in
    fpf "#!/bin/sh -\n";
    fpf "\n";

    (match uefi_firmware with
     | None -> ()
     | Some (_, vars_template) ->
        fpf "# Make a copy of the UEFI variables template\n";
        fpf "uefi_vars=\"$(mktemp)\"\n";
        fpf "cp %s \"$uefi_vars\"\n" (quote vars_template);
        fpf "\n"
    );

    fpf "/usr/libexec/qemu-kvm";
    fpf "%s-no-user-config -nodefaults" nl;
    fpf "%s-name %s" nl (quote source.s_name);
    fpf "%s-machine accel=kvm:tcg" nl;

    (match uefi_firmware with
     | None -> ()
     | Some (code, _) ->
        fpf "%s-drive if=pflash,format=raw,file=%s,readonly" nl (quote code);
        fpf "%s-drive if=pflash,format=raw,file=\"$uefi_vars\"" nl
    );

    fpf "%s-m %Ld" nl (source.s_memory /^ 1024L /^ 1024L);
    if source.s_vcpu > 1 then
      fpf "%s-smp %d" nl source.s_vcpu;

    let make_disk if_name i = function
    | BusSlotEmpty -> ()

    | BusSlotTarget t ->
       let qemu_quoted_filename = String.replace t.target_file "," ",," in
       let drive_param =
          sprintf "file=%s,format=%s,if=%s,index=%d,media=disk"
                  qemu_quoted_filename t.target_format if_name i in
       fpf "%s-drive %s" nl (quote drive_param)

    | BusSlotRemovable { s_removable_type = CDROM } ->
       let drive_param =
          sprintf "format=raw,if=%s,index=%d,media=cdrom" if_name i in
       fpf "%s-drive %s" nl (quote drive_param)

    | BusSlotRemovable { s_removable_type = Floppy } ->
       let drive_param =
          sprintf "format=raw,if=%s,index=%d,media=floppy" if_name i in
       fpf "%s-drive %s" nl (quote drive_param)
    in
    Array.iteri (make_disk "virtio") target_buses.target_virtio_blk_bus;
    Array.iteri (make_disk "ide") target_buses.target_ide_bus;

    let make_scsi i = function
    | BusSlotEmpty -> ()

    | BusSlotTarget t ->
       let qemu_quoted_filename = String.replace t.target_file "," ",," in
       let drive_param =
          sprintf "file=%s,format=%s,if=scsi,bus=0,unit=%d,media=disk"
                  qemu_quoted_filename t.target_format i in
       fpf "%s-drive %s" nl (quote drive_param)

    | BusSlotRemovable { s_removable_type = CDROM } ->
       let drive_param =
          sprintf "format=raw,if=scsi,bus=0,unit=%d,media=cdrom" i in
       fpf "%s-drive %s" nl (quote drive_param)

    | BusSlotRemovable { s_removable_type = Floppy } ->
       let drive_param =
          sprintf "format=raw,if=scsi,bus=0,unit=%d,media=floppy" i in
       fpf "%s-drive %s" nl (quote drive_param)
    in
    Array.iteri make_scsi target_buses.target_scsi_bus;

    let net_bus =
      match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio-net-pci"
      | E1000 -> "e1000"
      | RTL8139 -> "rtl8139" in
    iteri (
      fun i nic ->
        fpf "%s-netdev user,id=net%d" nl i;
        fpf "%s-device %s,netdev=net%d%s" nl
          net_bus i (match nic.s_mac with None -> "" | Some mac -> ",mac=" ^ mac)
    ) source.s_nics;

    (* Add a display. *)
    (match source.s_display with
    | None -> ()
    | Some display ->
      (match display.s_display_type with
      | Window ->
        fpf "%s-display gtk" nl
      | VNC ->
        fpf "%s-display vnc=:0" nl
      | Spice ->
        fpf "%s-spice port=%d,addr=127.0.0.1" nl
        (match display.s_port with None -> 5900 | Some p -> p)
      );
      fpf "%s-vga %s" nl
        (match guestcaps.gcaps_video with Cirrus -> "cirrus" | QXL -> "qxl")
    );

    (* Add a sound card. *)
    (match source.s_sound with
     | None -> ()
     | Some { s_sound_model = model } ->
        if qemu_supports_sound_card model then (
          match model with
          | AC97      -> fpf "%s-device AC97" nl
          | ES1370    -> fpf "%s-device ES1370" nl
          | ICH6      -> fpf "%s-device intel-hda -device hda-duplex" nl
          | ICH9      -> fpf "%s-device ich9-intel-hda" nl
          | PCSpeaker -> fpf "%s-soundhw pcspk" nl (* not qdev-ified *)
          | SB16      -> fpf "%s-device sb16" nl
          | USBAudio  -> fpf "%s-device usb-audio" nl
        )
    );

    (* Add a serial console to Linux guests. *)
    if inspect.i_type = "linux" then
      fpf "%s-serial stdio" nl;

    fpf "\n";

    close_out chan;

    Unix.chmod file 0o755;

    (* If --qemu-boot option was specified then we should boot the guest. *)
    if qemu_boot then (
      let cmd = sprintf "%s &" (quote file) in
      ignore (shell_command cmd)
    )
end

let output_qemu = new output_qemu
let () = Modules_list.register_output_module "qemu"
