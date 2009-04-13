(* libguestfs OCaml bindings
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *)

open Unix

let () =
  let g = Guestfs.create () in

  let fd = openfile "test.img" [O_WRONLY;O_CREAT;O_NOCTTY;O_TRUNC] 0o666 in
  ftruncate fd (500 * 1024 * 1024);
  close fd;

  Guestfs.add_drive g "test.img";
  Guestfs.launch g;
  Guestfs.wait_ready g;

  Guestfs.pvcreate g "/dev/sda";
  Guestfs.vgcreate g "VG" [|"/dev/sda"|];
  Guestfs.lvcreate g "LV1" "VG" 200;
  Guestfs.lvcreate g "LV2" "VG" 200;

  let lvs = Guestfs.lvs g in
  if lvs <> [|"/dev/VG/LV1"; "/dev/VG/LV2"|] then
    failwith "Guestfs.lvs returned incorrect result";

  Guestfs.sync g;
  Guestfs.close g;
  unlink "test.img"
