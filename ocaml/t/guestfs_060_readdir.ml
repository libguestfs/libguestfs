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
  ftruncate fd (10 * 1024 * 1024);
  close fd;

  Guestfs.add_drive g "test.img";
  Guestfs.launch g;
  Guestfs.wait_ready g;

  Guestfs.sfdisk g "/dev/sda" 0 0 0 [|","|];
  Guestfs.mkfs g "ext2" "/dev/sda1";
  Guestfs.mount g "/dev/sda1" "/";
  Guestfs.mkdir g "/p";
  Guestfs.touch g "/q";

  let dirs = Guestfs.readdir g "/" in
  let dirs = Array.to_list dirs in
  let cmp { Guestfs.name = n1 } { Guestfs.name = n2 } = compare n1 n2 in
  let dirs = List.sort cmp dirs in
  let dirs = List.map (
    fun { Guestfs.name = name; Guestfs.ftyp = ftyp } -> (name, ftyp)
  ) dirs in

  if dirs <> [ ".", 'd';
	       "..", 'd';
	       "lost+found", 'd';
	       "p", 'd';
	       "q", 'r' ] then
    failwith "Guestfs.readdir returned incorrect result";

  Guestfs.close g;
  unlink "test.img"
