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

(* Detect which kernels are installed and offered by the bootloader. *)

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Types

module G = Guestfs

(* Kernel information. *)
type kernel_info = {
  ki_app : G.application2;
  ki_name : string;
  ki_version : string;
  ki_arch : string;
  ki_vmlinuz : string;
  ki_vmlinuz_stat : G.statns;
  ki_initrd : string option;
  ki_modpath : string;
  ki_modules : string list;
  ki_supports_virtio_blk : bool;
  ki_supports_virtio_net : bool;
  ki_supports_virtio_rng : bool;
  ki_supports_virtio_balloon : bool;
  ki_supports_isa_pvpanic : bool;
  ki_is_xen_pv_only_kernel : bool;
  ki_is_debug : bool;
  ki_config_file : string option;
}

let print_kernel_info chan prefix ki =
  let fpf fs = output_string chan prefix; fprintf chan fs in
  fprintf chan "* %s %s (%s)\n" ki.ki_name ki.ki_version ki.ki_arch;
  fpf "%s\n" ki.ki_vmlinuz;
  fpf "%s\n" (match ki.ki_initrd with None -> "no initrd" | Some s -> s);
  fpf "%s\n" (match ki.ki_config_file with None -> "no config" | Some s -> s);
  fpf "%s\n" ki.ki_modpath;
  fpf "%d modules found\n" (List.length ki.ki_modules);
  fpf "virtio: blk=%b net=%b rng=%b balloon=%b\n"
      ki.ki_supports_virtio_blk ki.ki_supports_virtio_net
      ki.ki_supports_virtio_rng ki.ki_supports_virtio_balloon;
  fpf "pvpanic=%b xen=%b debug=%b\n"
      ki.ki_supports_isa_pvpanic ki.ki_is_xen_pv_only_kernel ki.ki_is_debug

let rex_ko = PCRE.compile "\\.k?o(?:\\.xz)?$"
let rex_ko_extract = PCRE.compile "/([^/]+)\\.k?o(?:\\.xz)?$"

let detect_kernels (g : G.guestfs) inspect family bootloader =
  (* What kernel/kernel-like packages are installed on the current guest? *)
  let installed_kernels : kernel_info list =
    let check_config feature = function
      | None -> false
      | Some config ->
        let prefix = "^CONFIG_" ^ String.uppercase_ascii feature ^ "=" in
        let lines = g#grep ~extended:true prefix config in
        let lines = Array.to_list lines in
        match lines with
        | [] -> false
        | line :: _ ->
          let kind = snd (String.split "=" line) in
          (match kind with
          | "m" | "y" -> true
          | _ -> false
          )
    in
    let rex_initrd =
      if family = `Debian_family then
        PCRE.compile "^initrd.img-.*$"
      else
        PCRE.compile "^initr(?:d|amfs)-.*(?:\\.img)?$" in
    List.filter_map (
      function
      | { G.app2_name = name } as app
          when name = "kernel" || String.is_prefix name "kernel-"
               || String.is_prefix name "linux-image-" ->
        (try
           (* For each kernel, list the files directly owned by the kernel. *)
           let files = Linux.file_list_of_package g inspect app in

           if files = [] then (
             warning (f_"package ‘%s’ contains no files") name;
             None
           )
           else (
             (* Which of these is the kernel itself? *)
             let vmlinuz = List.find (
               fun filename -> String.is_prefix filename "/boot/vmlinuz-"
             ) files in
             (* Which of these is the modpath? *)
             let modpath = List.find (
               fun filename ->
                 String.length filename >= 14 &&
                   String.is_prefix filename "/lib/modules/"
             ) files in

             (* Check vmlinuz & modpath exist. *)
             if not (g#is_dir ~followsymlinks:true modpath) then
               raise Not_found;
             let vmlinuz_stat =
               try g#statns vmlinuz with G.Error _ -> raise Not_found in

             (* Get/construct the version.  XXX Read this from kernel file. *)
             let version =
               let prefix_len = String.length "/lib/modules/" in
               String.sub modpath prefix_len (String.length modpath - prefix_len) in

             (* Find the initramfs which corresponds to the kernel.
              * Since the initramfs is built at runtime, and doesn't have
              * to be covered by the RPM file list, this is basically
              * guesswork.
              *)
             let initrd =
               let files = g#ls "/boot" in
               let files = Array.to_list files in
               let files =
                 List.filter (fun n -> PCRE.matches rex_initrd n) files in
               let files =
                 List.filter (
                   fun n ->
                     String.find n version >= 0
                 ) files in
               (* Don't consider kdump initramfs images (RHBZ#1138184). *)
               let files =
                 List.filter (fun n -> String.find n "kdump" == -1) files in
               (* If several files match, take the shortest match.  This
                * handles the case where we have a mix of same-version non-Xen
                * and Xen kernels:
                *   initrd-2.6.18-308.el5.img
                *   initrd-2.6.18-308.el5xen.img
                * and kernel 2.6.18-308.el5 (non-Xen) will match both
                * (RHBZ#1141145).
                *)
               let cmp a b = compare (String.length a) (String.length b) in
               let files = List.sort cmp files in
               match files with
               | [] ->
                 warning (f_"no initrd was found in /boot matching %s %s.")
                   name version;
                 None
               | x :: _ -> Some ("/boot/" ^ x) in

             (* Get all modules, which might include custom-installed
              * modules that don't appear in 'files' list above.
              *)
             let modules = g#find modpath in
             let modules = Array.to_list modules in
             let modules =
               List.filter (fun m -> PCRE.matches rex_ko m) modules in
             assert (List.length modules > 0);

             (* Determine the kernel architecture by looking at the
              * architecture of an arbitrary kernel module.
              *)
             let arch =
               let any_module = modpath ^ List.hd modules in
               g#file_architecture any_module in

             (* Just return the module names, without path or extension. *)
             let modules = List.filter_map (
               fun m ->
                 if PCRE.matches rex_ko_extract m then
                   Some (PCRE.sub 1)
                 else
                   None
             ) modules in
             assert (List.length modules > 0);

             let config_file =
               let cfg = "/boot/config-" ^ version in
               if List.mem cfg files then Some cfg
               else None in

             let kernel_supports what kconf =
               List.mem what modules || check_config kconf config_file in

             let supports_virtio_blk =
               kernel_supports "virtio_blk" "VIRTIO_BLK" in
             let supports_virtio_net =
               kernel_supports "virtio_net" "VIRTIO_NET" in
             let supports_virtio_rng =
               kernel_supports "virtio-rng" "HW_RANDOM_VIRTIO" in
             let supports_virtio_balloon =
               kernel_supports "virtio_balloon" "VIRTIO_BALLOON" in
             let supports_isa_pvpanic =
               kernel_supports "pvpanic" "PVPANIC" in
             let is_xen_pv_only_kernel =
               check_config "X86_XEN" config_file ||
               check_config "X86_64_XEN" config_file in

             (* If the package name is like "kernel-debug", then it's
              * a debug kernel.
              *)
             let is_debug =
               String.is_suffix app.G.app2_name "-debug" ||
               String.is_suffix app.G.app2_name "-dbg" in

             Some {
               ki_app  = app;
               ki_name = name;
               ki_version = version;
               ki_arch = arch;
               ki_vmlinuz = vmlinuz;
               ki_vmlinuz_stat = vmlinuz_stat;
               ki_initrd = initrd;
               ki_modpath = modpath;
               ki_modules = modules;
               ki_supports_virtio_blk = supports_virtio_blk;
               ki_supports_virtio_net = supports_virtio_net;
               ki_supports_virtio_rng = supports_virtio_rng;
               ki_supports_virtio_balloon = supports_virtio_balloon;
               ki_supports_isa_pvpanic = supports_isa_pvpanic;
               ki_is_xen_pv_only_kernel = is_xen_pv_only_kernel;
               ki_is_debug = is_debug;
               ki_config_file = config_file;
             }
           )

         with Not_found -> None
        )

      | _ -> None
    ) inspect.i_apps in

  if verbose () then (
    eprintf "installed kernel packages in this guest:\n";
    List.iter (print_kernel_info stderr "\t") installed_kernels;
    flush stderr
  );

  if installed_kernels = [] then
    error (f_"no installed kernel packages were found.\n\nThis probably indicates that %s was unable to inspect this guest properly.")
      prog;

  (* Now the difficult bit.  Get the bootloader kernels.  The first in this
   * list is the default booting kernel.
   *)
  let bootloader_kernels : kernel_info list =
    let vmlinuzes = bootloader#list_kernels in

    (* Map these to installed kernels. *)
    List.filter_map (
      fun vmlinuz ->
        try
          let statbuf = g#statns vmlinuz in
          let kernel =
            List.find (
              fun { ki_vmlinuz_stat = s } ->
                statbuf.G.st_dev = s.G.st_dev && statbuf.G.st_ino = s.G.st_ino
            ) installed_kernels in
          Some kernel
        with
        | Not_found -> None
        | G.Error msg as exn ->
          (* If it isn't "no such file or directory", then re-raise it. *)
          if g#last_errno () <> G.Errno.errno_ENOENT then raise exn;
          warning (f_"ignoring kernel %s in bootloader, as it does not exist.")
            vmlinuz;
          None
    ) vmlinuzes in

  if verbose () then (
    eprintf "kernels offered by the bootloader in this guest (first in list is default):\n";
    List.iter (print_kernel_info stderr "\t") bootloader_kernels;
    flush stderr
  );

  if bootloader_kernels = [] then
    error (f_"no kernels were found in the bootloader configuration.\n\nThis probably indicates that %s was unable to parse the bootloader configuration of this guest.")
      prog;

  bootloader_kernels
