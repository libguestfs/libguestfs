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

(* Types.  See types.mli for documentation. *)

type source = {
  s_hypervisor : source_hypervisor;
  s_name : string;
  s_orig_name : string;
  s_memory : int64;
  s_vcpu : int;
  s_features : string list;
  s_firmware : source_firmware;
  s_display : source_display option;
  s_sound : source_sound option;
  s_disks : source_disk list;
  s_removables : source_removable list;
  s_nics : source_nic list;
}
and source_hypervisor =
  | QEmu | KQemu | KVM | Xen | LXC | UML | OpenVZ
  | Test | VMware | HyperV | VBox | Phyp | Parallels
  | Bhyve
  | Physical (* used by virt-p2v *)
  | UnknownHV (* used by -i disk *)
  | OtherHV of string
and source_firmware =
  | BIOS
  | UEFI
  | UnknownFirmware
and source_disk = {
  s_disk_id : int;
  s_qemu_uri : string;
  s_format : string option;
  s_controller : s_controller option;
}
and s_controller = Source_IDE | Source_SCSI | Source_virtio_blk
and source_removable = {
  s_removable_type : s_removable_type;
  s_removable_controller : s_controller option;
  s_removable_slot : int option;
}
and s_removable_type = CDROM | Floppy
and source_nic = {
  s_mac : string option;
  s_vnet : string;
  s_vnet_orig : string;
  s_vnet_type : vnet_type;
}
and vnet_type = Bridge | Network
and source_display = {
  s_display_type : s_display_type;
  s_keymap : string option;
  s_password : string option;
  s_listen : s_display_listen;
  s_port : int option;
}
and s_display_type = Window | VNC | Spice
and s_display_listen =
  | LNone
  | LAddress of string
  | LNetwork of string

and source_sound = {
  s_sound_model : source_sound_model;
}
and source_sound_model =
  AC97 | ES1370 | ICH6 | ICH9 | PCSpeaker | SB16 | USBAudio

let rec string_of_source s =
  sprintf "    source name: %s
hypervisor type: %s
         memory: %Ld (bytes)
       nr vCPUs: %d
   CPU features: %s
       firmware: %s
        display: %s
          sound: %s
disks:
%s
removable media:
%s
NICs:
%s
"
    s.s_name
    (string_of_source_hypervisor s.s_hypervisor)
    s.s_memory
    s.s_vcpu
    (String.concat "," s.s_features)
    (string_of_source_firmware s.s_firmware)
    (match s.s_display with
    | None -> ""
    | Some display -> string_of_source_display display)
    (match s.s_sound with
    | None -> ""
    | Some sound -> string_of_source_sound sound)
    (String.concat "\n" (List.map string_of_source_disk s.s_disks))
    (String.concat "\n" (List.map string_of_source_removable s.s_removables))
    (String.concat "\n" (List.map string_of_source_nic s.s_nics))

and string_of_source_hypervisor = function
  | QEmu -> "qemu"
  | KQemu -> "kqemu"
  | KVM -> "kvm"
  | Xen -> "xen"
  | LXC -> "lxc"
  | UML -> "uml"
  | OpenVZ -> "openvz"
  | Test -> "test"
  | VMware -> "vmware"
  | HyperV -> "hyperv"
  | VBox -> "vbox"
  | Phyp -> "phyp"
  | Parallels -> "parallels"
  | Bhyve -> "bhyve"
  | Physical -> "physical"
  | UnknownHV -> "unknown"
  | OtherHV s -> s

and source_hypervisor_of_string = function
  | "qemu" -> QEmu
  | "kqemu" -> KQemu
  | "kvm" -> KVM
  | "xen" -> Xen
  | "lxc" -> LXC
  | "uml" -> UML
  | "openvz" -> OpenVZ
  | "test" -> Test
  | "vmware" -> VMware
  | "hyperv" -> HyperV
  | "vbox" -> VBox
  | "phyp" -> Phyp
  | "parallels" -> Parallels
  | "bhyve" -> Bhyve
  | "physical" -> Physical
  | "unknown" -> OtherHV "unknown" (* because `UnknownHV is for internal use *)
  | s -> OtherHV s

and string_of_source_firmware = function
  | BIOS -> "bios"
  | UEFI -> "uefi"
  | UnknownFirmware -> "unknown"

and string_of_source_disk { s_qemu_uri = qemu_uri; s_format = format;
                            s_controller = controller } =
  sprintf "\t%s%s%s"
    qemu_uri
    (match format with
    | None -> ""
    | Some format -> " (" ^ format ^ ")")
    (match controller with
    | None -> ""
    | Some controller -> " [" ^ string_of_controller controller ^ "]")

and string_of_controller = function
  | Source_IDE -> "ide"
  | Source_SCSI -> "scsi"
  | Source_virtio_blk -> "virtio"

and string_of_source_removable { s_removable_type = typ;
                                 s_removable_controller = controller;
                                 s_removable_slot = i } =
  sprintf "\t%s%s%s"
    (match typ with CDROM -> "CD-ROM" | Floppy -> "Floppy")
    (match controller with
    | None -> ""
    | Some controller -> " [" ^ string_of_controller controller ^ "]")
    (match i with None -> "" | Some i -> sprintf " in slot %d" i)

and string_of_source_nic { s_mac = mac; s_vnet = vnet; s_vnet_type = typ } =
  sprintf "\t%s \"%s\"%s"
    (match typ with Bridge -> "Bridge" | Network -> "Network")
    vnet
    (match mac with
    | None -> ""
    | Some mac -> " mac: " ^ mac)

and string_of_source_display { s_display_type = typ;
                               s_keymap = keymap; s_password = password;
                               s_listen = listen } =
  sprintf "%s%s%s%s"
    (match typ with Window -> "window" | VNC -> "vnc" | Spice -> "spice")
    (match keymap with None -> "" | Some km -> " " ^ km)
    (match password with None -> "" | Some _ -> " with password")
    (match listen with
    | LNone -> ""
    | LAddress a -> sprintf " listening on address %s" a
    | LNetwork n -> sprintf " listening on network %s" n
    )

and string_of_source_sound { s_sound_model = model } =
  string_of_source_sound_model model

(* NB: This function must produce names compatible with libvirt.  The
 * documentation for libvirt is incomplete, look instead at the
 * sources.
 *)
and string_of_source_sound_model = function
  | AC97      -> "ac97"
  | ES1370    -> "es1370"
  | ICH6      -> "ich6"
  | ICH9      -> "ich9"
  | PCSpeaker -> "pcspk"
  | SB16      -> "sb16"
  | USBAudio  -> "usb"

type overlay = {
  ov_overlay_file : string;
  ov_sd : string;
  ov_virtual_size : int64;
  ov_source : source_disk;
}

let string_of_overlay ov =
  sprintf "\
ov_overlay_file = %s
ov_sd = %s
ov_virtual_size = %Ld
ov_source = %s
"
    ov.ov_overlay_file
    ov.ov_sd
    ov.ov_virtual_size
    ov.ov_source.s_qemu_uri

type target = {
  target_file : string;
  target_format : string;
  target_estimated_size : int64 option;
  target_actual_size : int64 option;
  target_overlay : overlay;
}

let string_of_target t =
  sprintf "\
target_file = %s
target_format = %s
target_estimated_size = %s
target_overlay = %s
target_overlay.ov_source = %s
"
    t.target_file
    t.target_format
    (match t.target_estimated_size with
    | None -> "None" | Some i -> Int64.to_string i)
    t.target_overlay.ov_overlay_file
    t.target_overlay.ov_source.s_qemu_uri

type target_firmware = TargetBIOS | TargetUEFI

let string_of_target_firmware = function
  | TargetBIOS -> "bios"
  | TargetUEFI -> "uefi"

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
  i_mountpoints : (string * string) list;
  i_apps : Guestfs.application2 list;
  i_apps_map : Guestfs.application2 list StringMap.t;
  i_uefi : bool;
}

let string_of_inspect inspect =
  sprintf "\
i_root = %s
i_type = %s
i_distro = %s
i_arch = %s
i_major_version = %d
i_minor_version = %d
i_package_format = %s
i_package_management = %s
i_product_name = %s
i_product_variant = %s
i_uefi = %b
" inspect.i_root
  inspect.i_type
  inspect.i_distro
  inspect.i_arch
  inspect.i_major_version
  inspect.i_minor_version
  inspect.i_package_format
  inspect.i_package_management
  inspect.i_product_name
  inspect.i_product_variant
  inspect.i_uefi

type mpstat = {
  mp_dev : string;
  mp_path : string;
  mp_statvfs : Guestfs.statvfs;
  mp_vfs : string;
}

let print_mpstat chan { mp_dev = dev; mp_path = path;
                        mp_statvfs = s; mp_vfs = vfs } =
  fprintf chan "mountpoint statvfs %s %s (%s):\n" dev path vfs;
  fprintf chan "  bsize=%Ld blocks=%Ld bfree=%Ld bavail=%Ld\n"
    s.Guestfs.bsize s.Guestfs.blocks s.Guestfs.bfree s.Guestfs.bavail

type guestcaps = {
  gcaps_block_bus : guestcaps_block_type;
  gcaps_net_bus : guestcaps_net_type;
  gcaps_video : guestcaps_video_type;
  gcaps_arch : string;
  gcaps_acpi : bool;
}
and guestcaps_block_type = Virtio_blk | IDE
and guestcaps_net_type = Virtio_net | E1000 | RTL8139
and guestcaps_video_type = QXL | Cirrus

let string_of_guestcaps gcaps =
  sprintf "\
gcaps_block_bus = %s
gcaps_net_bus = %s
gcaps_video = %s
gcaps_arch = %s
gcaps_acpi = %b
" (match gcaps.gcaps_block_bus with
   | Virtio_blk -> "virtio"
   | IDE -> "ide")
  (match gcaps.gcaps_net_bus with
   | Virtio_net -> "virtio-net"
   | E1000 -> "e1000"
   | RTL8139 -> "rtl8139")
  (match gcaps.gcaps_video with
   | QXL -> "qxl"
   | Cirrus -> "cirrus")
  gcaps.gcaps_arch
  gcaps.gcaps_acpi

type target_buses = {
  target_virtio_blk_bus : target_bus_slot array;
  target_ide_bus : target_bus_slot array;
  target_scsi_bus : target_bus_slot array;
  target_floppy_bus : target_bus_slot array;
}

and target_bus_slot =
  | BusSlotEmpty
  | BusSlotTarget of target
  | BusSlotRemovable of source_removable

let string_of_target_bus_slots bus_name slots =
  let slots =
    Array.mapi (
      fun slot_nr slot ->
        sprintf "%s slot %d:\n" bus_name slot_nr ^
          (match slot with
           | BusSlotEmpty -> "\t(slot empty)\n"
           | BusSlotTarget t -> string_of_target t
           | BusSlotRemovable r -> string_of_source_removable r ^ "\n"
          )
    ) slots in
  String.concat "" (Array.to_list slots)

let string_of_target_buses buses =
  string_of_target_bus_slots "virtio-blk" buses.target_virtio_blk_bus ^
  string_of_target_bus_slots "ide" buses.target_ide_bus ^
  string_of_target_bus_slots "scsi" buses.target_scsi_bus

type root_choice = AskRoot | SingleRoot | FirstRoot | RootDev of string

type output_allocation = Sparse | Preallocated

type vmtype = Desktop | Server

class virtual input = object
  method virtual as_options : string
  method virtual source : unit -> source
  method adjust_overlay_parameters (_ : overlay) = ()
end

class virtual output = object
  method virtual as_options : string
  method virtual prepare_targets : source -> target list -> target list
  method virtual supported_firmware : target_firmware list
  method check_target_firmware (_ : guestcaps) (_ : target_firmware) = ()
  method check_target_free_space (_ : source) (_ : target list) = ()
  method disk_create = (open_guestfs ())#disk_create
  method virtual create_metadata : source -> target list -> target_buses -> guestcaps -> inspect -> target_firmware -> unit
  method keep_serial_console = true
end
