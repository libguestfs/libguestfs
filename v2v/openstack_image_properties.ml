(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

(* Convert metadata to a list of OpenStack image properties. *)

open Printf

open Std_utils

open Types

let create source target_buses guestcaps inspect target_firmware =
  let properties = ref [] in

  List.push_back_list properties [
    "architecture", guestcaps.gcaps_arch;
    "hypervisor_type", "kvm";
    "vm_mode", "hvm";

    "hw_disk_bus",
    (match guestcaps.gcaps_block_bus with
     | Virtio_blk -> "virtio"
     | Virtio_SCSI -> "scsi"
     | IDE -> "ide");
    "hw_vif_model",
    (match guestcaps.gcaps_net_bus with
     | Virtio_net -> "virtio"
     | E1000 -> "e1000"
     | RTL8139 -> "rtl8139");
    "hw_video_model",
    (match guestcaps.gcaps_video with
     | QXL -> "qxl"
     | Cirrus -> "cirrus");
    "hw_machine_type",
    (match guestcaps.gcaps_machine with
     | I440FX -> "pc"
     | Q35 -> "q35"
     | Virt -> "virt");

    "os_type", inspect.i_type;
    "os_distro",
    (match inspect.i_distro with
     (* https://docs.openstack.org/python-glanceclient/latest/cli/property-keys.html *)
     | "archlinux" -> "arch"
     | "sles" -> "sled"
     | x -> x (* everything else is the same in libguestfs and OpenStack*)
    )
  ];

  (match source.s_cpu_topology with
   | None ->
      List.push_back properties ("hw_cpu_sockets", "1");
      List.push_back properties ("hw_cpu_cores", string_of_int source.s_vcpu);
   | Some { s_cpu_sockets = sockets; s_cpu_cores = cores;
            s_cpu_threads = threads } ->
      List.push_back properties ("hw_cpu_sockets", string_of_int sockets);
      List.push_back properties ("hw_cpu_cores", string_of_int cores);
      List.push_back properties ("hw_cpu_threads", string_of_int threads);
  );

  (match guestcaps.gcaps_block_bus with
   | Virtio_SCSI ->
      List.push_back properties ("hw_scsi_model", "virtio-scsi")
   | Virtio_blk | IDE -> ()
  );

  (match inspect.i_major_version, inspect.i_minor_version with
   | 0, 0 -> ()
   | x, 0 -> List.push_back properties ("os_version", string_of_int x)
   | x, y -> List.push_back properties ("os_version", sprintf "%d.%d" x y)
  );

  if guestcaps.gcaps_virtio_rng then
    List.push_back properties ("hw_rng_model", "virtio");
  (* XXX Neither memory balloon nor pvpanic are supported by
   * Glance at this time.
   *)

  (match target_firmware with
   | TargetBIOS -> ()
   | TargetUEFI ->
      List.push_back properties ("hw_firmware_type", "uefi")
  );

  !properties
