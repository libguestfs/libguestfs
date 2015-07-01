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

(* Find virtio-win driver files from an unpacked or mounted virtio-win
 * directory, or from a virtio-win.iso file. The location of drivers
  varies between releases of virtio-win and also across Fedora and
  RHEL so try to be robust to changes.
 *)
type virtio_win_driver_file = {
  (* Base filename, eg. "netkvm.sys".  Always lowercase. *)
  vwd_filename : string;
  (* Return the contents of this file. *)
  vwd_get_contents : unit -> string;

  (* Various fields that classify this driver: *)

  vwd_os_major : int;           (* Windows version. *)
  vwd_os_minor : int;
  vwd_os_variant : vwd_os_variant;
  vwd_os_arch : string;         (* Architecture, eg "i386", "x86_64". *)
  vwd_extension : string;       (* File extension (lowercase), eg. "sys" "inf"*)

  (* Original source of file (for debugging only). *)
  vwd_original_source : string;
}
and vwd_os_variant = Vwd_client | Vwd_server | Vwd_any_variant

let print_virtio_win_driver_file vwd =
  printf "%s [%d,%d,%s,%s,%s] from %s\n"
         vwd.vwd_filename
         vwd.vwd_os_major vwd.vwd_os_minor
         (match vwd.vwd_os_variant with
          | Vwd_client -> "client" | Vwd_server -> "server"
          | Vwd_any_variant -> "any")
         vwd.vwd_os_arch
         vwd.vwd_extension
         vwd.vwd_original_source

let find_virtio_win_drivers ~verbose virtio_win =
  let is_regular_file path = (* NB: follows symlinks. *)
    try (Unix.stat path).Unix.st_kind = Unix.S_REG
    with Unix.Unix_error _ -> false
  in

  let files =
    if is_directory virtio_win then (
      let cmd = sprintf "cd %s && find -type f" (quote virtio_win) in
      let paths = external_command ~prog cmd in
      List.map (
        fun path ->
          let abs_path = virtio_win // path in
          (path, abs_path,
           Filename.basename path,
           fun () -> read_whole_file abs_path)
      ) paths
    )
    else if is_regular_file virtio_win then (
      try
        let g = new Guestfs.guestfs () in
        if verbose then (
          g#set_trace true;
          g#set_verbose true;
        );
        g#add_drive_opts virtio_win ~readonly:true;
        g#launch ();
        g#mount_ro "/dev/sda" "/";
        let paths = g#find "/" in
        let paths = Array.to_list paths in
        let paths = List.map ((^) "/") paths in
        let paths = List.filter (g#is_file ~followsymlinks:false) paths in
        List.map (
          fun path ->
            let i = String.rindex path '/' in
            let len = String.length path in
            let basename = String.sub path (i+1) (len - (i+1)) in
            (path, sprintf "%s:%s" virtio_win path,
             basename,
             fun () -> g#read_file path)
        ) paths
      with Guestfs.Error msg ->
        error (f_"%s: cannot open virtio-win ISO file: %s") virtio_win msg
    )
    else [] in

  let files =
    filter_map (
      fun (path, original_source, basename, get_contents) ->
        try
          (* Lowercased path, since the ISO may contain upper or lowercase
           * path elements.  XXX This won't work if paths contain non-ASCII.
           *)
          let lc_path = String.lowercase path in
          let lc_basename = String.lowercase basename in

          let extension =
            let i = String.rindex lc_basename '.' in
            let len = String.length lc_basename in
            String.sub lc_basename (i+1) (len - (i+1)) in

          (* Skip files without specific extensions. *)
          if extension <> "cat" && extension <> "inf" &&
               extension <> "pdb" && extension <> "sys" then
            raise Not_found;

          (* Using the full path, work out what version of Windows
           * this driver is for.  Paths can be things like:
           * "NetKVM/2k12R2/amd64/netkvm.sys" or
           * "./drivers/amd64/Win2012R2/netkvm.sys".
           * Note we check lowercase paths.
           *)
          let pathelem elem = string_find lc_path ("/" ^ elem ^ "/") >= 0 in
          let arch =
            if pathelem "x86" || pathelem "i386" then "i386"
            else if pathelem "amd64" then "x86_64"
            else raise Not_found in
          let os_major, os_minor, os_variant =
            if pathelem "xp" || pathelem "winxp" then
              (5, 1, Vwd_any_variant)
            else if pathelem "2k3" || pathelem "win2003" then
              (5, 2, Vwd_any_variant)
            else if pathelem "vista" then
              (6, 0, Vwd_client)
            else if pathelem "2k8" || pathelem "win2008" then
              (6, 0, Vwd_server)
            else if pathelem "w7" || pathelem "win7" then
              (6, 1, Vwd_client)
            else if pathelem "2k8r2" || pathelem "win2008r2" then
              (6, 1, Vwd_server)
            else if pathelem "w8" || pathelem "win8" then
              (6, 2, Vwd_client)
            else if pathelem "2k12" || pathelem "win2012" then
              (6, 2, Vwd_server)
            else if pathelem "w8.1" || pathelem "win8.1" then
              (6, 3, Vwd_client)
            else if pathelem "2k12r2" || pathelem "win2012r2" then
              (6, 3, Vwd_server)
            else if pathelem "w10" || pathelem "win10" then
              (10, 0, Vwd_client)
            else
              raise Not_found in

          Some {
            vwd_filename = lc_basename;
            vwd_get_contents = get_contents;
            vwd_os_major = os_major;
            vwd_os_minor = os_minor;
            vwd_os_variant = os_variant;
            vwd_os_arch = arch;
            vwd_extension = extension;
            vwd_original_source = original_source;
          }

        with Not_found -> None
    ) files in

  files

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
