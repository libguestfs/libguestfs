(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

let quote = Filename.quote

(* Parse an xpath expression and return a string/int.  Returns
 * [Some v], or [None] if the expression doesn't match.
 *)
let xpath_eval parsefn xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  if Xml.xpathobj_nr_nodes obj < 1 then None
  else (
    let node = Xml.xpathobj_node obj 0 in
    let str = Xml.node_as_string node in
    try Some (parsefn str)
    with Failure "int_of_string" ->
      error (f_"expecting XML expression to return an integer (expression: %s, matching string: %s)")
            expr str
  )

external identity : 'a -> 'a = "%identity"

let xpath_string = xpath_eval identity
let xpath_int = xpath_eval int_of_string
let xpath_int64 = xpath_eval Int64.of_string

(* Parse an xpath expression and return a string/int; if the expression
 * doesn't match, return the default.
 *)
let xpath_eval_default parsefn xpath expr default =
  match xpath_eval parsefn xpath expr with
  | None -> default
  | Some s -> s

let xpath_string_default = xpath_eval_default identity
let xpath_int_default = xpath_eval_default int_of_string
let xpath_int64_default = xpath_eval_default Int64.of_string

external drive_name : int -> string = "v2v_utils_drive_name"
external drive_index : string -> int = "v2v_utils_drive_index"

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
  | Types.ICH6
  | Types.ICH9
  | Types.PCSpeaker
    -> true
  | Types.ES1370
  | Types.SB16
  | Types.USBAudio
    -> false

external ovmf_i386_firmware : unit -> (string * string) list = "v2v_utils_ovmf_i386_firmware"
external ovmf_x86_64_firmware : unit -> (string * string) list = "v2v_utils_ovmf_x86_64_firmware"
external aavmf_firmware : unit -> (string * string) list = "v2v_utils_aavmf_firmware"

(* Find the UEFI firmware. *)
let find_uefi_firmware guest_arch =
  let files =
    (* The lists of firmware are actually defined in src/utils.c. *)
    match guest_arch with
    | "i386" | "i486" | "i586" | "i686" -> ovmf_i386_firmware ()
    | "x86_64" -> ovmf_x86_64_firmware ()
    | "aarch64" -> aavmf_firmware ()
    | arch ->
       error (f_"don't know how to convert UEFI guests for architecture %s")
             guest_arch in
  let rec loop = function
    | [] ->
       error (f_"cannot find firmware for UEFI guests.\n\nYou probably need to install OVMF, or Gerd's firmware repo (https://www.kraxel.org/repos/), or AAVMF (if using aarch64)")
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

let remove_duplicates xs =
  let h = Hashtbl.create (List.length xs) in
  let rec loop = function
    | [] -> []
    | x :: xs when Hashtbl.mem h x -> xs
    | x :: xs -> Hashtbl.add h x true; x :: loop xs
  in
  loop xs

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

external shell_unquote : string -> string = "v2v_utils_shell_unquote"
