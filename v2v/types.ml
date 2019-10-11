(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

(* Types.  See types.mli for documentation. *)

type source = {
  s_hypervisor : source_hypervisor;
  s_name : string;
  s_orig_name : string;
  s_genid : string option;
  s_memory : int64;
  s_vcpu : int;
  s_cpu_vendor : string option;
  s_cpu_model : string option;
  s_cpu_topology : source_cpu_topology option;
  s_features : string list;
  s_firmware : source_firmware;
  s_display : source_display option;
  s_video : source_video option;
  s_sound : source_sound option;
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
and s_controller = Source_IDE | Source_SATA | Source_SCSI |
                   Source_virtio_blk | Source_virtio_SCSI
and source_removable = {
  s_removable_type : s_removable_type;
  s_removable_controller : s_controller option;
  s_removable_slot : int option;
}
and s_removable_type = CDROM | Floppy
and source_nic = {
  s_mac : string option;
  s_nic_model : s_nic_model option;
  s_vnet : string;
  s_vnet_type : vnet_type;
  s_mapping_explanation : string option;
}
and s_nic_model = Source_other_nic of string |
                  Source_rtl8139 | Source_e1000 | Source_virtio_net
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
  | LNoListen
  | LAddress of string
  | LNetwork of string
  | LSocket of string option
  | LNone

and source_video = Source_other_video of string |
                   Source_Cirrus | Source_QXL

and source_sound = {
  s_sound_model : source_sound_model;
}
and source_sound_model =
  AC97 | ES1370 | ICH6 | ICH9 | PCSpeaker | SB16 | USBAudio
and source_cpu_topology = {
  s_cpu_sockets : int;
  s_cpu_cores : int;
  s_cpu_threads : int;
}

let rec string_of_source s source_disks =
  sprintf "    source name: %s
hypervisor type: %s
       VM genid: %s
         memory: %Ld (bytes)
       nr vCPUs: %d
     CPU vendor: %s
      CPU model: %s
   CPU topology: %s
   CPU features: %s
       firmware: %s
        display: %s
          video: %s
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
    (Option.default "" s.s_genid)
    s.s_memory
    s.s_vcpu
    (Option.default "" s.s_cpu_vendor)
    (Option.default "" s.s_cpu_model)
    (match s.s_cpu_topology with
    | None -> ""
    | Some topology -> string_of_source_cpu_topology topology)
    (String.concat "," (List.sort compare s.s_features))
    (string_of_source_firmware s.s_firmware)
    (match s.s_display with
    | None -> ""
    | Some display -> string_of_source_display display)
    (match s.s_video with
    | None -> ""
    | Some video -> string_of_source_video video)
    (match s.s_sound with
    | None -> ""
    | Some sound -> string_of_source_sound sound)
    (String.concat "\n" (List.map string_of_source_disk source_disks))
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
  | Source_SATA -> "sata"
  | Source_SCSI -> "scsi"
  | Source_virtio_blk -> "virtio-blk"
  | Source_virtio_SCSI -> "virtio-scsi"

and string_of_source_removable { s_removable_type = typ;
                                 s_removable_controller = controller;
                                 s_removable_slot = i } =
  sprintf "\t%s%s%s"
    (match typ with CDROM -> "CD-ROM" | Floppy -> "Floppy")
    (match controller with
    | None -> ""
    | Some controller -> " [" ^ string_of_controller controller ^ "]")
    (match i with None -> "" | Some i -> sprintf " in slot %d" i)

and string_of_source_nic { s_mac = mac; s_nic_model = model; s_vnet = vnet;
                           s_vnet_type = typ } =
  sprintf "\t%s \"%s\"%s%s"
    (string_of_vnet_type typ)
    vnet
    (match mac with
    | None -> ""
    | Some mac -> " mac: " ^ mac)
    (match model with
    | None -> ""
    | Some model -> " [" ^ string_of_nic_model model ^ "]")

and string_of_vnet_type = function
  | Bridge -> "Bridge"
  | Network -> "Network"

and string_of_nic_model = function
  | Source_virtio_net -> "virtio"
  | Source_e1000 -> "e1000"
  | Source_rtl8139 -> "rtl8139"
  | Source_other_nic model -> model

and string_of_source_display { s_display_type = typ;
                               s_keymap = keymap; s_password = password;
                               s_listen = listen } =
  sprintf "%s%s%s%s"
    (match typ with Window -> "window" | VNC -> "vnc" | Spice -> "spice")
    (match keymap with None -> "" | Some km -> " " ^ km)
    (match password with None -> "" | Some _ -> " with password")
    (match listen with
    | LNoListen -> ""
    | LAddress a -> sprintf " listening on address %s" a
    | LNetwork n -> sprintf " listening on network %s" n
    | LSocket (Some s) -> sprintf " listening on Unix domain socket %s" s
    | LSocket None -> sprintf " listening on automatically created Unix domain socket"
    | LNone -> " listening on private fd"
    )

and string_of_source_video = function
  | Source_QXL -> "qxl"
  | Source_Cirrus -> "cirrus"
  | Source_other_video video -> video

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

and string_of_source_cpu_topology { s_cpu_sockets; s_cpu_cores;
                                    s_cpu_threads } =
  sprintf "sockets: %d cores/socket: %d threads/core: %d"
    s_cpu_sockets s_cpu_cores s_cpu_threads

type disk_stats = {
  mutable target_estimated_size : int64 option;
  mutable target_actual_size : int64 option;
}

type overlay = {
  ov_overlay_file : string;
  ov_sd : string;
  ov_virtual_size : int64;
  ov_source : source_disk;
  ov_stats : disk_stats;
}

let string_of_overlay ov =
  sprintf "             overlay file: %s
      overlay device name: %s
overlay virtual disk size: %Ld
  overlay source qemu URI: %s
    target estimated size: %s
       target actual size: %s
"
    ov.ov_overlay_file
    ov.ov_sd
    ov.ov_virtual_size
    ov.ov_source.s_qemu_uri
    (match ov.ov_stats.target_estimated_size with
    | None -> "None" | Some i -> Int64.to_string i)
    (match ov.ov_stats.target_actual_size with
    | None -> "None" | Some i -> Int64.to_string i)

type target = {
  target_file : target_file;
  target_format : string;
  target_overlay : overlay;
}
and target_file =
  | TargetFile of string
  | TargetURI of string

let string_of_target t =
  sprintf "          target file: %s
        target format: %s
"
    (match t.target_file with
     | TargetFile s -> "[file] " ^ s
     | TargetURI s -> "[qemu] " ^ s)
    t.target_format

type target_firmware = TargetBIOS | TargetUEFI

let string_of_target_firmware = function
  | TargetBIOS -> "bios"
  | TargetUEFI -> "uefi"

type i_firmware =
  | I_BIOS
  | I_UEFI of string list

type inspect = {
  i_root : string;
  i_type : string;
  i_distro : string;
  i_osinfo : string;
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
  i_firmware : i_firmware;
  i_windows_systemroot : string;
  i_windows_software_hive : string;
  i_windows_system_hive : string;
  i_windows_current_control_set : string;
}

let string_of_inspect inspect =
  sprintf "\
i_root = %s
i_type = %s
i_distro = %s
i_osinfo = %s
i_arch = %s
i_major_version = %d
i_minor_version = %d
i_package_format = %s
i_package_management = %s
i_product_name = %s
i_product_variant = %s
i_firmware = %s
i_windows_systemroot = %s
i_windows_software_hive = %s
i_windows_system_hive = %s
i_windows_current_control_set = %s
" inspect.i_root
  inspect.i_type
  inspect.i_distro
  inspect.i_osinfo
  inspect.i_arch
  inspect.i_major_version
  inspect.i_minor_version
  inspect.i_package_format
  inspect.i_package_management
  inspect.i_product_name
  inspect.i_product_variant
  (match inspect.i_firmware with
   | I_BIOS -> "BIOS"
   | I_UEFI devices -> sprintf "UEFI [%s]" (String.concat ", " devices))
  inspect.i_windows_systemroot
  inspect.i_windows_software_hive
  inspect.i_windows_system_hive
  inspect.i_windows_current_control_set

type guestcaps = {
  gcaps_block_bus : guestcaps_block_type;
  gcaps_net_bus : guestcaps_net_type;
  gcaps_video : guestcaps_video_type;
  gcaps_virtio_rng : bool;
  gcaps_virtio_balloon : bool;
  gcaps_isa_pvpanic : bool;
  gcaps_machine : guestcaps_machine;
  gcaps_arch : string;
  gcaps_acpi : bool;
}
and requested_guestcaps = {
  rcaps_block_bus : guestcaps_block_type option;
  rcaps_net_bus : guestcaps_net_type option;
  rcaps_video : guestcaps_video_type option;
}
and guestcaps_block_type = Virtio_blk | Virtio_SCSI | IDE
and guestcaps_net_type = Virtio_net | E1000 | RTL8139
and guestcaps_video_type = QXL | Cirrus
and guestcaps_machine = I440FX | Q35 | Virt

let string_of_block_type = function
  | Virtio_blk -> "virtio-blk"
  | Virtio_SCSI -> "virtio-scsi"
  | IDE -> "ide"
let string_of_net_type = function
  | Virtio_net -> "virtio-net"
  | E1000 -> "e1000"
  | RTL8139 -> "rtl8139"
let string_of_video = function
  | QXL -> "qxl"
  | Cirrus -> "cirrus"
let string_of_machine = function
  | I440FX -> "i440fx"
  | Q35 -> "q35"
  | Virt -> "virt"

let string_of_guestcaps gcaps =
  sprintf "\
gcaps_block_bus = %s
gcaps_net_bus = %s
gcaps_video = %s
gcaps_machine = %s
gcaps_arch = %s
gcaps_acpi = %b
" (string_of_block_type gcaps.gcaps_block_bus)
  (string_of_net_type gcaps.gcaps_net_bus)
  (string_of_video gcaps.gcaps_video)
  (string_of_machine gcaps.gcaps_machine)
  gcaps.gcaps_arch
  gcaps.gcaps_acpi

let string_of_requested_guestcaps rcaps =
  sprintf "\
rcaps_block_bus = %s
rcaps_net_bus = %s
rcaps_video = %s
" (match rcaps.rcaps_block_bus with
   | None -> "unspecified"
   | Some block_type -> (string_of_block_type block_type))
  (match rcaps.rcaps_net_bus with
   | None -> "unspecified"
   | Some net_type -> (string_of_net_type net_type))
  (match rcaps.rcaps_video with
   | None -> "unspecified"
   | Some video -> (string_of_video video))

type target_buses = {
  target_virtio_blk_bus : target_bus_slot array;
  target_ide_bus : target_bus_slot array;
  target_scsi_bus : target_bus_slot array;
  target_floppy_bus : target_bus_slot array;
}

and target_bus_slot =
  | BusSlotEmpty
  | BusSlotDisk of source_disk
  | BusSlotRemovable of source_removable

let string_of_target_bus_slots bus_name slots =
  let slots =
    Array.mapi (
      fun slot_nr slot ->
        sprintf "%s slot %d:\n" bus_name slot_nr ^
          (match slot with
           | BusSlotEmpty -> "\t(slot empty)\n"
           | BusSlotDisk d -> string_of_source_disk d
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

type bandwidth =
| StaticBandwidth of string
| DynamicBandwidth of string option * string

type static_ip = {
  if_mac_addr : string;
  if_ip_address : string;
  if_default_gateway : string option;
  if_prefix_length : int option;
  if_nameservers : string list;
}

class virtual input = object
  method precheck () = ()
  method virtual as_options : string
  method virtual source : ?bandwidth:bandwidth -> unit -> (source * source_disk list)
end

class virtual output = object
  method precheck () = ()
  method virtual as_options : string
  method virtual supported_firmware : target_firmware list
  method check_target_firmware (_ : guestcaps) (_ : target_firmware) = ()
  method override_output_format (_ : overlay) = (None : string option)
  method virtual prepare_targets : string -> (string * overlay) list -> target_file list
  method disk_create = (open_guestfs ())#disk_create
  method disk_copied (_ : target) (_ : int) (_ : int) = ()
  method virtual create_metadata : source -> target list -> target_buses -> guestcaps -> inspect -> target_firmware -> unit
  method keep_serial_console = true
  method install_rhev_apt = false
end

type output_settings = < keep_serial_console : bool;
                         install_rhev_apt : bool >
