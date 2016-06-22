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

open Common_utils
open Common_gettext.Gettext

open Types

let rec target_bus_assignment source targets guestcaps =
  let virtio_blk_bus = ref [| |]
  and ide_bus = ref [| |]
  and scsi_bus = ref [| |]
  and floppy_bus = ref [| |] in

  (* Add the fixed disks (targets) to either the virtio-blk or IDE bus,
   * depending on whether the guest has virtio drivers or not.
   *)
  let () =
    let bus =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk -> virtio_blk_bus
      | IDE -> ide_bus in
    iteri (
      fun i t ->
        let t = BusSlotTarget t in
        insert bus i t
    ) targets in

  (* Now we have to assign the removable disks.  These go in the
   * same slot they originally occupied, except in two cases: (1) That
   * slot is now occupied by a target disk, or (2) we don't
   * have information about the original slot.  In these cases
   * insert the disk in the next empty slot in that bus.
   *)

  (* Split the removables into a list of devices that desire a
   * particular slot, and those that don't care.  Assign the first
   * group first so they have a greater chance of getting the
   * desired slot.
   *)
  let removables_desire, removables_no_desire =
    List.partition (
      function
      | { s_removable_slot = Some _ } -> true
      | { s_removable_slot = None } -> false
    ) source.s_removables in

  let assign_removables removables =
    List.iter (
      fun r ->
        let t = BusSlotRemovable r in
        let bus =
          match r.s_removable_type with
          | Floppy -> floppy_bus
          | CDROM ->
             match r.s_removable_controller with
             | None -> ide_bus (* Wild guess, but should be safe. *)
             | Some Source_virtio_blk -> virtio_blk_bus
             | Some Source_IDE -> ide_bus
             | Some Source_SCSI -> scsi_bus in

        match r.s_removable_slot with
        | None ->
           ignore (insert_after bus 0 t)
        | Some desired_slot_nr ->
           if not (insert_after bus desired_slot_nr t) then
             warning (f_"removable %s device in slot %d clashes with another disk, so it has been moved to a higher numbered slot on the same bus.  This may mean that this removable device has a different name inside the guest (for example a CD-ROM originally called /dev/hdc might move to /dev/hdd, or from D: to E: on a Windows guest).")
                     (match r.s_removable_type with
                      | CDROM -> s_"CD-ROM"
                      | Floppy -> s_"floppy disk")
                     desired_slot_nr
    ) removables
  in
  assign_removables removables_desire;
  assign_removables removables_no_desire;

  { target_virtio_blk_bus = !virtio_blk_bus;
    target_ide_bus = !ide_bus;
    target_scsi_bus = !scsi_bus;
    target_floppy_bus = !floppy_bus }

(* Insert a slot into the bus array, making the array bigger if necessary. *)
and insert bus i slot =
  let oldbus = !bus in
  let oldlen = Array.length oldbus in
  if i >= oldlen then (
    bus := Array.make (i+1) BusSlotEmpty;
    Array.blit oldbus 0 !bus 0 oldlen
  );
  assert (!bus.(i) = BusSlotEmpty);
  !bus.(i) <- slot

(* Insert a slot into the bus, but if the desired slot is not empty, then
 * increment the slot number until we find an empty one.  Returns
 * true if we got the desired slot.
 *)
and insert_after bus i slot =
  if slot_is_empty bus i then (
    insert bus i slot; true
  ) else (
    ignore (insert_after bus (i+1) slot); false
  )

(* Return true if slot i is empty in the bus. *)
and slot_is_empty bus i = i >= Array.length !bus || !bus.(i) = BusSlotEmpty
