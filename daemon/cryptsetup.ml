(* guestfs-inspection
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Printf
open Unix

open Std_utils

open Utils

let cryptsetup_open ?(readonly = false) ?crypttype device key mapname =
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
  let keyfile, chan = Filename.open_temp_file "crypt" ".key" in
  output_string chan key;
  close_out chan;

  let args = ref [] in
  List.push_back_list args ["-d"; keyfile];
  if readonly then List.push_back args "--readonly";
  List.push_back_list args ["open"; device; mapname; "--type"; crypttype];

  (* Make sure we always remove the temporary file. *)
  protect ~f:(fun () -> ignore (command "cryptsetup" !args))
    ~finally:(fun () -> unlink keyfile);

  udev_settle ()

let cryptsetup_close device =
  (* Must be /dev/mapper/... *)
  if not (String.is_prefix device "/dev/mapper/") then
    failwithf "%s: you must call this on the /dev/mapper device created by cryptsetup-open" device;

  let mapname = String.sub device 12 (String.length device - 12) in
  ignore (command "cryptsetup" ["close"; mapname]);

  udev_settle ()

(* Deprecated APIs for backwards compatibility. *)
let luks_open device key mapname =
  cryptsetup_open ~crypttype:"luks" device key mapname
let luks_open_ro device key mapname =
  cryptsetup_open ~crypttype:"luks" ~readonly:true device key mapname
let luks_close = cryptsetup_close
