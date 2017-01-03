(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(* Utilities used in virt-v2v only. *)

open Printf

open Common_gettext.Gettext
open Common_utils

external drive_name : int -> string = "v2v_utils_drive_name"
external drive_index : string -> int = "v2v_utils_drive_index"

external shell_unquote : string -> string = "v2v_utils_shell_unquote"

(* Map guest architecture found by inspection to the architecture
 * that KVM must emulate.  Note for x86 we assume a 64 bit hypervisor.
 *)
let kvm_arch = function
  | "i386" | "i486" | "i586" | "i686"
  | "x86_64" -> "x86_64"
  | "unknown" -> "x86_64" (* most likely *)
  | arch -> arch

(* Does qemu support the given sound card? *)
let qemu_supports_sound_card = function
  | Types.AC97
  | Types.ES1370
  | Types.ICH6
  | Types.ICH9
  | Types.PCSpeaker
  | Types.SB16
  | Types.USBAudio
    -> true

(* Find the UEFI firmware. *)
let find_uefi_firmware guest_arch =
  let files =
    (* The lists of firmware are actually defined in src/uefi.c. *)
    match guest_arch with
    | "i386" | "i486" | "i586" | "i686" -> Uefi.uefi_i386_firmware
    | "x86_64" -> Uefi.uefi_x86_64_firmware
    | "aarch64" -> Uefi.uefi_aarch64_firmware
    | arch ->
       error (f_"don't know how to convert UEFI guests for architecture %s")
             guest_arch in
  let rec loop = function
    | [] ->
       error (f_"cannot find firmware for UEFI guests.\n\nYou probably need to install OVMF, or Gerd's firmware repo (https://www.kraxel.org/repos/), or AAVMF (if using aarch64)")
    | ({ Uefi.code = code; vars = vars_template } as ret) :: rest ->
       if Sys.file_exists code && Sys.file_exists vars_template then ret
       else loop rest
  in
  loop files

let compare_app2_versions app1 app2 =
  let i = compare app1.Guestfs.app2_epoch app2.Guestfs.app2_epoch in
  if i <> 0 then i
  else (
    let i =
      compare_version app1.Guestfs.app2_version app2.Guestfs.app2_version in
    if i <> 0 then i
    else
      compare_version app1.Guestfs.app2_release app2.Guestfs.app2_release
  )

let du filename =
  (* There's no OCaml binding for st_blocks, so run coreutils 'du'. *)
  let cmd =
    sprintf "du --block-size=1 %s | awk '{print $1}'" (quote filename) in
  (* XXX This can call error and so exit, but it would be preferable
   * to raise an exception here.
   *)
  let lines = external_command cmd in
  match lines with
  | line::_ -> Int64.of_string line
  | [] -> invalid_arg filename
