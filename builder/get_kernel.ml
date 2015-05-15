(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Utils

module G = Guestfs

open Printf

(* Originally:
 * http://rwmj.wordpress.com/2013/09/13/get-kernel-and-initramfs-from-a-disk-image/
 *)
let rec get_kernel ?format ?output disk =
  let g = new G.guestfs () in
  if trace () then g#set_trace true;
  if verbose () then g#set_verbose true;
  g#add_drive_opts ?format ~readonly:true disk;
  g#launch ();

  let roots = g#inspect_os () in
  if Array.length roots = 0 then
    error (f_"get-kernel: no operating system found");
  if Array.length roots > 1 then
    error (f_"get-kernel: dual/multi-boot images are not supported by this tool");
  let root = roots.(0) in

  (* Mount up the disks. *)
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (
    fun (mp, dev) ->
      try g#mount_ro dev mp
      with Guestfs.Error msg -> warning (f_"%s (ignored)") msg
  ) mps;

  (* Get all kernels and initramfses. *)
  let glob w = Array.to_list (g#glob_expand w) in
  let kernels = glob "/boot/vmlinuz-*" in
  let initrds = glob "/boot/initramfs-*" in

  (* Old RHEL: *)
  let initrds = if initrds <> [] then initrds else glob "/boot/initrd-*" in

  (* Debian/Ubuntu: *)
  let initrds = if initrds <> [] then initrds else glob "/boot/initrd.img-*" in

  (* Sort by version to get the latest version as first element. *)
  let kernels = List.rev (List.sort compare_version kernels) in
  let initrds = List.rev (List.sort compare_version initrds) in

  if kernels = [] then
    error (f_"no kernel found");

  (* Download the latest. *)
  let outputdir =
    match output with
    | None -> Filename.current_dir_name
    | Some dir -> dir in
  let kernel_in = List.hd kernels in
  let kernel_out = outputdir // Filename.basename kernel_in in
  printf "download: %s -> %s\n%!" kernel_in kernel_out;
  g#download kernel_in kernel_out;

  if initrds <> [] then (
    let initrd_in = List.hd initrds in
    let initrd_out = outputdir // Filename.basename initrd_in in
    printf "download: %s -> %s\n%!" initrd_in initrd_out;
    g#download initrd_in initrd_out
  );

  (* Shutdown. *)
  g#shutdown ();
  g#close ()
