(* guestfs-inspection
 * Copyright (C) 2009-2026 Red Hat Inc.
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
open Unix

open Std_utils

open Utils

let cryptsetup_open ?(readonly = false) ?crypttype ?cipher device key mapname =
  (* Sanity check: /dev/mapper/mapname must not exist already.  Note
   * that the device-mapper control device (/dev/mapper/control) is
   * always there, so you can't ever have mapname == "control".
   *)
  let devmapper = sprintf "/dev/mapper/%s" mapname in
  if is_block_device devmapper then
    failwithf "%s: device already exists" devmapper;

  (* Heuristically determine the encryption type. *)
  let crypttype =
    match crypttype with
    | Some s -> s
    | None ->
       let t = Blkid.vfs_type (Mountable.of_device device) in
       match t with
       | "crypto_LUKS" -> "luks"
       | "BitLocker" -> "bitlk"
       | _ ->
          failwithf "%s: unknown encrypted device type" t in

  (* Write the key to a temporary file. *)
  let keyfile = write_key_to_tmp_file key in

  Fun.protect ~finally:(fun () -> unlink keyfile) (
    fun () ->
      let args = ref [] in
      List.push_back args "-d";
      List.push_back args keyfile;
      if readonly then List.push_back args "--readonly";
      List.push_back args "open";
      List.push_back args device;
      List.push_back args mapname;
      List.push_back args "--type";
      List.push_back args crypttype;
      Option.iter (fun s -> List.push_back_list args ["--cipher"; s]) cipher;
      ignore (command "cryptsetup" !args)
  );

  udev_settle ()

let cryptsetup_close device =
  (* Must be /dev/mapper/... *)
  if not (String.starts_with "/dev/mapper/" device) then
    failwithf "%s: you must call this on the /dev/mapper device created by cryptsetup-open" device;

  let mapname = String.sub device 12 (String.length device - 12) in
  ignore (command "cryptsetup" ["close"; mapname]);

  udev_settle ()
