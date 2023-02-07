(* libguestfs OCaml tests
 * Copyright (C) 2009-2023 Red Hat Inc.
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

let () =
  let g = new Guestfs.guestfs () in
  g#add_drive_scratch (Int64.of_int (500 * 1024 * 1024));
  g#launch ();

  g#pvcreate "/dev/sda";
  g#vgcreate "VG" [|"/dev/sda"|];
  g#lvcreate "LV1" "VG" 200;
  g#lvcreate "LV2" "VG" 200;

  let lvs = g#lvs () in
  if lvs <> [|"/dev/VG/LV1"; "/dev/VG/LV2"|] then
    failwith "Guestfs.lvs returned incorrect result";

  g#mkfs "ext2" "/dev/VG/LV1";
  g#mount "/dev/VG/LV1" "/";
  g#mkdir "/p";
  g#touch "/q";

  let dirs = g#readdir "/" in
  let dirs = Array.to_list dirs in
  let cmp { Guestfs.name = n1 } { Guestfs.name = n2 } = compare n1 n2 in
  let dirs = List.sort cmp dirs in
  let dirs = List.map (
    fun { Guestfs.name; ftyp } -> (name, ftyp)
  ) dirs in

  if dirs <> [ ".", 'd';
               "..", 'd';
               "lost+found", 'd';
               "p", 'd';
               "q", 'r' ] then
    failwith "Guestfs.readdir returned incorrect result";

  g#shutdown ();
  g#close ()

let () = Gc.compact ()
