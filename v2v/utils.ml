(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

let quote = Filename.quote

(* Quote XML <element attr='...'> content.  Note you must use single
 * quotes around the attribute.
 *)
let xml_quote_attr str =
  let str = String.replace str "&" "&amp;" in
  let str = String.replace str "'" "&apos;" in
  let str = String.replace str "<" "&lt;" in
  let str = String.replace str ">" "&gt;" in
  str

let xml_quote_pcdata str =
  let str = String.replace str "&" "&amp;" in
  let str = String.replace str "<" "&lt;" in
  let str = String.replace str ">" "&gt;" in
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

(* Parse an xpath expression and return a string/int.  Returns
 * Some v or None if the expression doesn't match.
 *)
let xpath_string xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  if Xml.xpathobj_nr_nodes obj < 1 then None
  else (
    let node = Xml.xpathobj_node obj 0 in
    Some (Xml.node_as_string node)
  )
let xpath_int xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  if Xml.xpathobj_nr_nodes obj < 1 then None
  else (
    let node = Xml.xpathobj_node obj 0 in
    let str = Xml.node_as_string node in
    try Some (int_of_string str)
    with Failure "int_of_string" ->
      error (f_"expecting XML expression to return an integer (expression: %s, matching string: %s)")
            expr str
  )
let xpath_int64 xpathctx expr =
  let obj = Xml.xpath_eval_expression xpathctx expr in
  if Xml.xpathobj_nr_nodes obj < 1 then None
  else (
    let node = Xml.xpathobj_node obj 0 in
    let str = Xml.node_as_string node in
    try Some (Int64.of_string str)
    with Failure "int_of_string" ->
      error (f_"expecting XML expression to return an integer (expression: %s, matching string: %s)")
            expr str
  )

(* Parse an xpath expression and return a string/int; if the expression
 * doesn't match, return the default.
 *)
let xpath_string_default xpathctx expr default =
  match xpath_string xpathctx expr with
  | None -> default
  | Some s -> s
let xpath_int_default xpathctx expr default =
  match xpath_int xpathctx expr with
  | None -> default
  | Some i -> i
let xpath_int64_default xpathctx expr default =
  match xpath_int64 xpathctx expr with
  | None -> default
  | Some i -> i

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
  | AC97
  | ES1370
  | ICH6
  | ICH9
  | PCSpeaker
  | SB16
  | USBAudio
    -> true

(* Find the UEFI firmware. *)
let find_uefi_firmware guest_arch =
  let files =
    match guest_arch with
    | "i386" | "i486" | "i586" | "i686" ->
       [ "/usr/share/edk2.git/ovmf-ia32/OVMF_CODE-pure-efi.fd",
         "/usr/share/edk2.git/ovmf-ia32/OVMF_VARS-pure-efi.fd" ]
    | "x86_64" ->
       [ "/usr/share/OVMF/OVMF_CODE.fd",
         "/usr/share/OVMF/OVMF_VARS.fd";
         "/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd",
         "/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd" ]
    | "aarch64" ->
       [ "/usr/share/AAVMF/AAVMF_CODE.fd",
         "/usr/share/AAVMF/AAVMF_VARS.fd";
         "/usr/share/edk2.git/aarch64/QEMU_EFI-pflash.raw",
         "/usr/share/edk2.git/aarch64/vars-template-pflash.raw" ]
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

(* Given a path of a file relative to the root of the directory tree
 * with virtio-win drivers, figure out if it's suitable for the
  specific Windows flavor of the current guest.
 *)
let virtio_iso_path_matches_guest_os path inspect =
  let { i_major_version = os_major; i_minor_version = os_minor;
        i_arch = arch; i_product_variant = os_variant } = inspect in
  try
    (* Lowercased path, since the ISO may contain upper or lowercase path
     * elements. *)
    let lc_path = String.lowercase_ascii path in
    let lc_basename = Filename.basename path in

    let extension =
      match last_part_of lc_basename '.' with
      | Some x -> x
      | None -> raise Not_found
    in

    (* Skip files without specific extensions. *)
    let extensions = ["cat"; "inf"; "pdb"; "sys"] in
    if not (List.mem extension extensions) then raise Not_found;

    (* Using the full path, work out what version of Windows
     * this driver is for.  Paths can be things like:
     * "NetKVM/2k12R2/amd64/netkvm.sys" or
     * "./drivers/amd64/Win2012R2/netkvm.sys".
     * Note we check lowercase paths.
     *)
    let pathelem elem = String.find lc_path ("/" ^ elem ^ "/") >= 0 in
    let p_arch =
      if pathelem "x86" || pathelem "i386" then "i386"
      else if pathelem "amd64" then "x86_64"
      else raise Not_found in

    let is_client os_variant = os_variant = "Client"
    and not_client os_variant = os_variant <> "Client"
    and any_variant os_variant = true in
    let p_os_major, p_os_minor, match_os_variant =
      if pathelem "xp" || pathelem "winxp" then
        (5, 1, any_variant)
      else if pathelem "2k3" || pathelem "win2003" then
        (5, 2, any_variant)
      else if pathelem "vista" then
        (6, 0, is_client)
      else if pathelem "2k8" || pathelem "win2008" then
        (6, 0, not_client)
      else if pathelem "w7" || pathelem "win7" then
        (6, 1, is_client)
      else if pathelem "2k8r2" || pathelem "win2008r2" then
        (6, 1, not_client)
      else if pathelem "w8" || pathelem "win8" then
        (6, 2, is_client)
      else if pathelem "2k12" || pathelem "win2012" then
        (6, 2, not_client)
      else if pathelem "w8.1" || pathelem "win8.1" then
        (6, 3, is_client)
      else if pathelem "2k12r2" || pathelem "win2012r2" then
        (6, 3, not_client)
      else if pathelem "w10" || pathelem "win10" then
        (10, 0, is_client)
      else
        raise Not_found in

    arch = p_arch && os_major = p_os_major && os_minor = p_os_minor &&
      match_os_variant os_variant

  with Not_found -> false

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
