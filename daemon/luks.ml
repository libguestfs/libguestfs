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

let rec luks_format device key keyslot =
  _luks_format device key keyslot

and luks_format_cipher device key keyslot cipher =
  _luks_format ~cipher device key keyslot

and _luks_format ?cipher device key keyslot =
  let tmp = write_key_to_tmp_file key in
  Fun.protect ~finally:(fun () -> unlink tmp) (
    fun () ->
      let args = ref [] in
      List.push_back args "-q";
      Option.iter (fun s -> List.push_back_list args ["--cipher"; s]) cipher;
      List.push_back args "--key-slot";
      List.push_back args (string_of_int keyslot);
      List.push_back args "luksFormat";
      List.push_back args device;
      List.push_back args tmp;
      ignore (command "cryptsetup" !args)
  );
  udev_settle ()

let luks_add_key device key newkey keyslot =
  let keyfile = write_key_to_tmp_file key
  and newkeyfile = write_key_to_tmp_file newkey in
  Fun.protect ~finally:(fun () -> unlink keyfile; unlink newkeyfile) (
    fun () ->
      let args = ref [] in
      List.push_back args "-q";
      List.push_back args "-d";
      List.push_back args keyfile;
      List.push_back args "--key-slot";
      List.push_back args (string_of_int keyslot);
      List.push_back args "luksAddKey";
      List.push_back args device;
      List.push_back args newkeyfile;
      ignore (command "cryptsetup" !args)
  )

let luks_kill_slot device key keyslot =
  let tmp = write_key_to_tmp_file key in
  Fun.protect ~finally:(fun () -> unlink tmp) (
    fun () ->
      let args = ref [] in
      List.push_back args "-q";
      List.push_back args "-d";
      List.push_back args tmp;
      List.push_back args "luksKillSlot";
      List.push_back args device;
      List.push_back args (string_of_int keyslot);
      ignore (command "cryptsetup" !args)
  )

(* Deprecated APIs for backwards compatibility. *)
let luks_open device key mapname =
  Cryptsetup.cryptsetup_open ~crypttype:"luks" device key mapname
let luks_open_ro device key mapname =
  Cryptsetup.cryptsetup_open ~crypttype:"luks" ~readonly:true device key mapname
let luks_close =
  Cryptsetup.cryptsetup_close
