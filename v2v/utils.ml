(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

open Types

let prog = Filename.basename Sys.executable_name
let error ?exit_code fs = error ~prog ?exit_code fs

let quote = Filename.quote

(* Quote XML <element attr='...'> content.  Note you must use single
 * quotes around the attribute.
 *)
let xml_quote_attr str =
  let str = replace_str str "&" "&amp;" in
  let str = replace_str str "'" "&apos;" in
  let str = replace_str str "<" "&lt;" in
  let str = replace_str str ">" "&gt;" in
  str

let xml_quote_pcdata str =
  let str = replace_str str "&" "&amp;" in
  let str = replace_str str "<" "&lt;" in
  let str = replace_str str ">" "&gt;" in
  str

(* URI quoting. *)
let uri_quote str =
  let len = String.length str in
  let xs = ref [] in
  for i = 0 to len-1 do
    xs :=
      (match str.[i] with
      | ('A'..'Z' | 'a'..'z' | '0'..'9' | '/' | '.' | '-') as c ->
        String.make 1 c
      | c ->
        sprintf "%%%02x" (Char.code c)
      ) :: !xs
  done;
  String.concat "" (List.rev !xs)

external drive_name : int -> string = "v2v_utils_drive_name"

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
  | AC97
  | ICH6
  | ICH9
  | PCSpeaker
    -> true
  | ES1370
  | SB16
  | USBAudio
    -> false

(* Find the UEFI firmware. *)
let find_uefi_firmware guest_arch =
  let files =
    match guest_arch with
    | "x86_64" ->
       [ "/usr/share/OVMF/OVMF_CODE.fd",
         "/usr/share/OVMF/OVMF_VARS.fd" ]
    | "aarch64" ->
       [ "/usr/share/AAVMF/AAVMF_CODE.fd",
         "/usr/share/AAVMF/AAVMF_VARS.fd" ]
    | arch ->
       error (f_"don't know how to convert UEFI guests for architecture %s")
             guest_arch in
  let rec loop = function
    | [] ->
       error (f_"cannot find firmware for UEFI guests.\n\nYou probably need to install OVMF, or AAVMF (if using aarch64)")
    | ((code, vars_template) as ret) :: rest ->
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

and compare_app2_version_min app1 (min_epoch, min_version, min_release) =
  let i = compare app1.Guestfs.app2_epoch min_epoch in
  if i <> 0 then i
  else (
    let i = compare_version app1.Guestfs.app2_version min_version in
    if i <> 0 then i
    else
      compare_version app1.Guestfs.app2_release min_release
  )

let remove_duplicates xs =
  let h = Hashtbl.create (List.length xs) in
  let rec loop = function
    | [] -> []
    | x :: xs when Hashtbl.mem h x -> xs
    | x :: xs -> Hashtbl.add h x true; x :: loop xs
  in
  loop xs
