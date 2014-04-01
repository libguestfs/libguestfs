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

module G = Guestfs

open Printf

open Common_gettext.Gettext

open Utils
open Types

(* Helper function for SUSE: remove (hdX,X) prefix from a path. *)
let remove_hd_prefix =
  let rex = Str.regexp "^(hd.*)\\(.*\\)" in
  Str.replace_first rex "\\1"

(* Helper function to check if guest is EFI. *)
let check_efi g =
  if Array.length (g#glob_expand "/boot/efi/EFI/*/grub.cfg") < 1 then
    raise Not_found;

  (* Check the first partition of each device looking for an EFI
   * boot partition. We can't be sure which device is the boot
   * device, so we just check them all.
   *)
  let devs = g#list_devices () in
  let devs = Array.to_list devs in
  List.find (
    fun dev ->
      try g#part_get_gpt_type dev 1 = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
      with G.Error _ -> false
  ) devs

(* Virtual grub superclass. *)
class virtual grub verbose (g : Guestfs.guestfs) inspect config_file =
object
  method virtual list_kernels : unit -> string list

  method virtual configure_console : unit -> unit
  method virtual remove_console : unit -> unit

  method private get_default_image () =
    let cmd =
      if g#exists "/sbin/grubby" then
        [| "grubby"; "--default-kernel" |]
      else
        [| "/usr/bin/perl"; "-MBootloader::Tools"; "-e"; "
             InitLibrary();
             my $default = Bootloader::Tools::GetDefaultSection();
             print $default->{image};
         " |] in
    match g#command cmd with
    | "" -> None
    | k ->
      let len = String.length k in
      let k =
        if len > 0 && k.[len-1] = '\n' then String.sub k 0 (len-1) else k in
      Some (remove_hd_prefix k)
end

(* Concrete implementation for grub1. *)
class grub1 verbose g inspect config_file grub_fs =
object (self)
  inherit grub verbose g inspect config_file

  method private grub_fs = grub_fs      (* grub filesystem prefix *)

  method list_kernels () =
    let paths =
      let expr = sprintf "/files%s/title/kernel" config_file in
      let paths = g#aug_match expr in
      let paths = Array.to_list paths in

      (* Get the default kernel from grub if it's set. *)
      let default =
        let expr = sprintf "/files%s/default" config_file in
        try
          let idx = g#aug_get expr in
          let idx = int_of_string idx in
          (* Grub indices are zero-based, augeas is 1-based. *)
          let expr = sprintf "/files%s/title[%d]/kernel" config_file (idx+1) in
          Some expr
        with Not_found -> None in

      (* If a default kernel was set, put it at the beginning of the paths
       * list.
       *)
      match default with
      | None -> paths
      | Some p -> p :: List.filter ((<>) p) paths in

    (* Remove duplicates. *)
    let paths =
      let checked = Hashtbl.create 13 in
      let rec loop = function
        | [] -> []
        | p :: ps when Hashtbl.mem checked p -> ps
        | p :: ps -> Hashtbl.add checked p true; p :: loop ps
      in
      loop paths in

    (* Resolve the Augeas paths to kernel filenames. *)
    let kernels = List.map g#aug_get paths in

    (* Make sure kernel does not begin with (hdX,X). *)
    let kernels = List.map remove_hd_prefix kernels in

    (* Prepend grub filesystem. *)
    let kernels = List.map ((^) grub_fs) kernels in

    (* Check the actual file exists. *)
    let kernels = List.filter (g#is_file ~followsymlinks:true) kernels in

    kernels

  method configure_console () =
    let rex = Str.regexp "\\(.*\\)\\b\\([xh]vc0\\)\\b\\(.*\\)" in
    let expr = sprintf "/files%s/title/kernel/console" config_file in

    let paths = g#aug_match expr in
    let paths = Array.to_list paths in
    List.iter (
      fun path ->
        let console = g#aug_get path in
        if Str.string_match rex console 0 then (
          let console = Str.global_replace rex "\\1ttyS0\\3" console in
          g#aug_set path console
        )
    ) paths;

    g#aug_save ()

  method remove_console () =
    let rex = Str.regexp "\\(.*\\)\\b\\([xh]vc0\\)\\b\\(.*\\)" in
    let expr = sprintf "/files%s/title/kernel/console" config_file in

    let rec loop = function
      | [] -> ()
      | path :: paths ->
        let console = g#aug_get path in
        if Str.string_match rex console 0 then (
          ignore (g#aug_rm path);
          (* All the paths are invalid, restart the loop. *)
          let paths = g#aug_match expr in
          let paths = Array.to_list paths in
          loop paths
        )
        else
          loop paths
    in
    let paths = g#aug_match expr in
    let paths = Array.to_list paths in
    loop paths;

    g#aug_save ()

end

(* Create a grub1 object. *)
let rec grub1 verbose (g : Guestfs.guestfs) inspect =
  let root = inspect.i_root in

  (* Look for a grub configuration file. *)
  let config_file =
    try
      List.find (
        fun file -> g#is_file ~followsymlinks:true file
      ) ["/boot/grub/menu.lst"; "/boot/grub/grub.conf"]
    with
      Not_found ->
        failwith (s_"no grub/grub1/grub-legacy configuration file was found") in

  (* Check for EFI and convert if found. *)
  (try let dev = check_efi g in grub1_convert_from_efi verbose g dev
   with Not_found -> ()
  );

  (* Find the path that has to be prepended to filenames in grub.conf
   * in order to make them absolute.
   *)
  let grub_fs =
    let mounts = g#inspect_get_mountpoints root in
    try
      List.find (
        fun path -> List.mem_assoc path mounts
      ) [ "/boot/grub"; "/boot" ]
    with Not_found -> "" in

  (* Ensure Augeas is reading the grub configuration file, and if not
   * then add it.
   *)
  let () =
    let incls = g#aug_match "/augeas/load/Grub/incl" in
    let incls = Array.to_list incls in
    let incls_contains_conf =
      List.exists (fun incl -> g#aug_get incl = config_file) incls in
    if not incls_contains_conf then (
      g#aug_set "/augeas/load/Grub/incl[last()+1]" config_file;
      Convert_linux_common.augeas_reload verbose g;
    ) in

  new grub1 verbose g inspect config_file grub_fs

(* Reinstall grub. *)
and grub1_convert_from_efi verbose g dev =
  g#cp "/etc/grub.conf" "/boot/grub/grub.conf";
  g#ln_sf "/boot/grub/grub.conf" "/etc/grub.conf";

  (* Reload Augeas to pick up new location of grub.conf. *)
  Convert_linux_common.augeas_reload verbose g;

  ignore (g#command [| "grub-install"; dev |])

(* Concrete implementation for grub2. *)
class grub2 verbose g inspect config_file =
object (self)
  inherit grub verbose g inspect config_file

  method list_kernels () =
    let files =
      (match self#get_default_image () with
      | None -> []
      | Some k -> [k]) @
        (* This is how the grub2 config generator enumerates kernels. *)
        Array.to_list (g#glob_expand "/boot/kernel-*") @
        Array.to_list (g#glob_expand "/boot/vmlinuz-*") @
        Array.to_list (g#glob_expand "/vmlinuz-*") in
    let rex = Str.regexp ".*\\.\\(dpkg-.*|rpmsave|rpmnew\\)$" in
    let files = List.filter (
      fun file -> not (Str.string_match rex file 0)
    ) files in
    files

  method private update_console ~remove =
    let rex = Str.regexp "\\(.*\\)\\bconsole=[xh]vc0\\b\\(.*\\)" in

    let grub_cmdline_expr =
      if g#exists "/etc/sysconfig/grub" then
        "/files/etc/sysconfig/grub/GRUB_CMDLINE_LINUX"
      else
        "/files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT" in

    (try
       let grub_cmdline = g#aug_get grub_cmdline_expr in
       let grub_cmdline =
         if Str.string_match rex grub_cmdline 0 then (
           if remove then
             Str.global_replace rex "\\1\\3" grub_cmdline
           else
             Str.global_replace rex "\\1console=ttyS0\\3" grub_cmdline
         )
         else grub_cmdline in
       g#aug_set grub_cmdline_expr grub_cmdline;
       g#aug_save ();

       ignore (g#command [| "grub2-mkconfig"; "-o"; config_file |])
     with
       G.Error msg ->
         eprintf (f_"%s: warning: could not update grub2 console: %s (ignored)\n")
           prog msg
    )

  method configure_console () = self#update_console ~remove:false
  method remove_console () = self#update_console ~remove:true
end

let rec grub2 verbose (g : Guestfs.guestfs) inspect =
  (* Look for a grub2 configuration file. *)
  let config_file = "/boot/grub2/grub.cfg" in
  if not (g#is_file ~followsymlinks:true config_file) then (
    let msg =
      sprintf (f_"no grub2 configuration file was found (expecting %s)")
        config_file in
    failwith msg
  );

  (* Check for EFI and convert if found. *)
  (try
     let dev = check_efi g in
     grub2_convert_from_efi verbose g inspect dev
   with Not_found -> ()
  );

  new grub2 verbose g inspect config_file

(* For grub2:
 * - Turn the EFI partition into a BIOS Boot Partition
 * - Remove the former EFI partition from fstab
 * - Install the non-EFI version of grub
 * - Install grub2 in the BIOS Boot Partition
 * - Regenerate grub.cfg
 *)
and grub2_convert_from_efi verbose g inspect dev =
  (* EFI systems boot using grub2-efi, and probably don't have the
   * base grub2 package installed.
   *)
  Convert_linux_common.install verbose g inspect ["grub2"];

  (* Relabel the EFI boot partition as a BIOS boot partition. *)
  g#part_set_gpt_type dev 1 "21686148-6449-6E6F-744E-656564454649";

  (* Delete the fstab entry for the EFI boot partition. *)
  let nodes = g#aug_match "/files/etc/fstab/*[file = '/boot/efi']" in
  let nodes = Array.to_list nodes in
  List.iter (fun node -> ignore (g#aug_rm node)) nodes;
  g#aug_save ();

  (* Install grub2 in the BIOS boot partition. This overwrites the
   * previous contents of the EFI boot partition.
   *)
  ignore (g#command [| "grub2-install"; dev |]);

  (* Re-generate the grub2 config, and put it in the correct place *)
  ignore (g#command [| "grub2-mkconfig"; "-o"; "/boot/grub2/grub.cfg" |])
