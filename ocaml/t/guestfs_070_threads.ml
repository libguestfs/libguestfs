(* libguestfs OCaml bindings
 * Copyright (C) 2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Unix

(* Start a background thread which does lots of allocation and
 * GC activity.
 *)
let thread = Thread.create (
  fun () ->
    while true do
      Gc.compact ();
      ignore (Array.init 1000 (fun i -> Thread.yield (); String.create (8*i)))
    done
) ()

let () =
  let g = Guestfs.create () in

  let fd = openfile "test.img" [O_WRONLY;O_CREAT;O_NOCTTY;O_TRUNC] 0o666 in
  ftruncate fd (500 * 1024 * 1024);
  close fd;

  (* Copy these strings so they're located on the heap and
   * subject to garbage collection.
   *)
  let s = String.copy "test.img" in
  Guestfs.add_drive_ro g s;
  Guestfs.launch g;

  let dev = String.copy "/dev/sda" in
  Guestfs.pvcreate g dev;
  let vg = String.copy "VG" in
  Guestfs.vgcreate g vg [|dev|];
  let s = String.copy "LV1" in
  Guestfs.lvcreate g s vg 200;
  let s = String.copy "LV2" in
  Guestfs.lvcreate g s vg 200;

  let lvs = Guestfs.lvs g in
  if lvs <> [|"/dev/VG/LV1"; "/dev/VG/LV2"|] then
    failwith "Guestfs.lvs returned incorrect result";

  let s = String.copy "ext3" in
  let lv = String.copy "/dev/VG/LV1" in
  Guestfs.mkfs g s lv;
  let s = String.copy "/" in
  Guestfs.mount_options g "" lv s;
  let s = String.copy "/test" in
  Guestfs.touch g s;

  Guestfs.umount_all g;
  Guestfs.sync g;
  Guestfs.close g;
  unlink "test.img";
  Gc.compact ();
  exit 0
