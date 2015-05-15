(* virt-sparsify
 * Copyright (C) 2011-2015 Red Hat Inc.
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

(* This is the virt-sparsify --in-place mode. *)

open Unix
open Printf

open Common_utils
open Common_gettext.Gettext

open Utils
open Cmdline

module G = Guestfs

let rec run disk format ignores machine_readable zeroes =
  (* Connect to libguestfs. *)
  let g = new G.guestfs () in
  if trace () then g#set_trace true;
  if verbose () then g#set_verbose true;

  try
    perform g disk format ignores machine_readable zeroes
  with
    G.Error msg as exn ->
      if g#last_errno () = G.Errno.errno_ENOTSUP then (
        (* for exit code 3, see man page *)
        error ~exit_code:3 (f_"discard/trim is not supported: %s") msg;
      )
      else raise exn

and perform g disk format ignores machine_readable zeroes =
  (* XXX Current limitation of the API.  Can remove this hunk in future. *)
  let format =
    match format with
    | Some _ -> format
    | None -> Some (g#disk_format disk) in

  g#add_drive ?format ~discard:"enable" disk;

  if not (quiet ()) then Progress.set_up_progress_bar ~machine_readable g;
  g#launch ();

  (* Discard non-ignored filesystems that we are able to mount, and
   * selected swap partitions.
   *)
  let filesystems = g#list_filesystems () in
  let filesystems = List.map fst filesystems in
  let filesystems = List.sort compare filesystems in

  let is_ignored fs =
    let fs = g#canonical_device_name fs in
    List.exists (fun fs' -> fs = g#canonical_device_name fs') ignores
  in

  let is_read_only_lv = is_read_only_lv g in

  List.iter (
    fun fs ->
      if not (is_ignored fs) && not (is_read_only_lv fs) then (
        if List.mem fs zeroes then (
          message (f_"Zeroing %s") fs;

          if not (g#blkdiscardzeroes fs) then
            g#zero_device fs;
          g#blkdiscard fs
        ) else (
          let mounted =
            try g#mount_options "discard" fs "/"; true
            with _ -> false in

          if mounted then (
            message (f_"Trimming %s") fs;

            g#fstrim "/"
          ) else (
            let is_linux_x86_swap =
              (* Look for the signature for Linux swap on i386.
               * Location depends on page size, so it definitely won't
               * work on non-x86 architectures (eg. on PPC, page size is
               * 64K).  Also this avoids hibernated swap space: in those,
               * the signature is moved to a different location.
               *)
              try g#pread_device fs 10 4086L = "SWAPSPACE2"
              with _ -> false in

            if is_linux_x86_swap then (
              message (f_"Clearing Linux swap on %s") fs;

              (* Don't use mkswap.  Just preserve the header containing
               * the label, UUID and swap format version (libguestfs
               * mkswap may differ from guest's own).
               *)
              let header = g#pread_device fs 4096 0L in
              g#blkdiscard fs;
              if g#pwrite_device fs header 0L <> 4096 then
                error (f_"pwrite: short write restoring swap partition header")
            )
          )
        );

        g#umount_all ()
      )
  ) filesystems;

  (* Discard unused space in volume groups. *)
  let vgs = g#vgs () in
  let vgs = Array.to_list vgs in
  let vgs = List.sort compare vgs in
  List.iter (
    fun vg ->
      if not (List.mem vg ignores) then (
        let lvname = string_random8 () in
        let lvdev = "/dev/" ^ vg ^ "/" ^ lvname in

        let created =
          try g#lvcreate_free lvname vg 100; true
          with _ -> false in

        if created then (
          message (f_"Discard space in volgroup %s") vg;

          g#blkdiscard lvdev;
          g#sync ();
          g#lvremove lvdev
        )
      )
  ) vgs;

  g#shutdown ();
  g#close ();

  (* Finished. *)
  message (f_"Sparsify in-place operation completed with no errors")
