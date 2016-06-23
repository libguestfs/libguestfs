(* virt-sparsify
 * Copyright (C) 2011-2016 Red Hat Inc.
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

(* This is the traditional virt-sparsify mode: We copy from a
 * source disk to a destination disk.
 *)

open Unix
open Printf

open Common_utils
open Common_gettext.Gettext

open Utils
open Cmdline

module G = Guestfs

type tmp_place =
| Directory of string | Block_device of string | Prebuilt_file of string

let run indisk outdisk check_tmpdir compress convert
    format ignores machine_readable option tmp_param zeroes =

  (* Once we have got past argument parsing and start to create
   * temporary files (including the potentially massive overlay file), we
   * need to catch SIGINT (^C) and exit cleanly so the temporary file
   * goes away.  Note that we don't delete temporaries in the signal
   * handler.
   *)
  let do_sigint _ = exit 1 in
  Sys.set_signal Sys.sigint (Sys.Signal_handle do_sigint);

  (* What should the output format be?  If the user specified an
   * input format, use that, else detect it from the source image.
   *)
  let output_format =
    match convert with
    | Some fmt -> fmt           (* user specified output conversion *)
    | None ->
      match format with
      | Some fmt -> fmt    (* user specified input format, use that *)
      | None ->
        (* Don't know, so we must autodetect. *)
        match (open_guestfs ())#disk_format indisk  with
        | "unknown" ->
          error (f_"cannot detect input disk format; use the --format parameter")
        | fmt -> fmt in

  (* Compression is not supported by raw output (RHBZ#852194). *)
  if output_format = "raw" && compress then
    error (f_"--compress cannot be used for raw output.  Remove this option or use --convert qcow2.");

  (* Use TMPDIR or --tmp parameter? *)
  let tmp_place =
    match tmp_param with
    | None -> Directory Filename.temp_dir_name (* $TMPDIR or /tmp *)
    | Some dir when is_directory dir -> Directory dir
    | Some dev when is_block_device dev -> Block_device dev
    | Some file when String.is_prefix file "prebuilt:" ->
      let file = String.sub file 9 (String.length file - 9) in
      if not (Sys.file_exists file) then
        error (f_"--tmp prebuilt:file: %s: file does not exist") file;
      let g = open_guestfs () in
      if g#disk_format file <> "qcow2" then
        error (f_"--tmp prebuilt:file: %s: file format is not qcow2") file;
      if not (g#disk_has_backing_file file) then
        error (f_"--tmp prebuilt:file: %s: file does not have backing file")
          file;
      Prebuilt_file file
    | Some path ->
      error (f_"--tmp parameter must point to a directory, block device or prebuilt file") in

  (* Check there is enough space in temporary directory. *)
  (match tmp_place with
  | Block_device _
  | Prebuilt_file _ -> ()
  | Directory tmpdir ->
    (* Get virtual size of the input disk. *)
    let virtual_size = (open_guestfs ())#disk_virtual_size indisk in
    debug "input disk virtual size is %Ld bytes (%s)"
          virtual_size (human_size virtual_size);

    let print_warning () =
      let free_space = StatVFS.free_space tmpdir in
      let extra_needed = virtual_size -^ free_space in
      if extra_needed > 0L then (
        warning (f_"\
There may not be enough free space on %s.
You may need to set TMPDIR to point to a directory with more free space.

Max needed: %s.  Free: %s.  May need another %s.

Note this is an overestimate.  If the guest disk is full of data
then not as much free space would be required.

You can ignore this warning or change it to a hard failure using the
--check-tmpdir=(ignore|continue|warn|fail) option.  See virt-sparsify(1).

%!")
          tmpdir (human_size virtual_size)
          (human_size free_space) (human_size extra_needed);
        true
      ) else false
    in

    match check_tmpdir with
    | `Ignore -> ()
    | `Continue -> ignore (print_warning ())
    | `Warn ->
      if print_warning () then (
        eprintf "Press RETURN to continue or ^C to quit.\n%!";
        ignore (read_line ())
      );
    | `Fail ->
      if print_warning () then (
        eprintf "Exiting because --check-tmpdir=fail was set.\n%!";
        exit 2
      )
  );

  (* Create the temporary overlay file. *)
  let overlaydisk =
    (match tmp_place with
    | Directory tmpdir ->
       message (f_"Create overlay file in %s to protect source disk") tmpdir
    | Block_device device ->
       message (f_"Create overlay device %s to protect source disk") device
    | Prebuilt_file file ->
       message (f_"Using prebuilt file %s as overlay") file
    );

    (* Create 'tmp' with the indisk as the backing file. *)
    let create tmp =
      let g = open_guestfs () in
      g#disk_create
        ~backingfile:indisk ?backingformat:format ~compat:"1.1"
        tmp "qcow2" Int64.minus_one
    in

    match tmp_place with
    | Directory temp_dir ->
      let tmp = Filename.temp_file ~temp_dir "sparsify" ".qcow2" in
      unlink_on_exit tmp;
      create tmp;
      tmp

    | Block_device device ->
      create device;
      device

    | Prebuilt_file file ->
      (* Don't create anything, use the prebuilt file as overlay. *)
      file in

  message (f_"Examine source disk");

  (* Connect to libguestfs. *)
  let g =
    let g = open_guestfs () in

    (* Note that the temporary overlay disk is always qcow2 format. *)
    g#add_drive ~format:"qcow2" ~readonly:false ~cachemode:"unsafe" overlaydisk;

    if not (quiet ()) then Progress.set_up_progress_bar ~machine_readable g;
    g#launch ();

    g in

  (* Modify SIGINT handler (set first above) to cancel the handle. *)
  let do_sigint _ =
    g#user_cancel ();
    exit 1
  in
  Sys.set_signal Sys.sigint (Sys.Signal_handle do_sigint);

  (* Write zeroes for non-ignored filesystems that we are able to mount,
   * and selected swap partitions.
   *)
  let filesystems = g#list_filesystems () in
  let btrfs_filesystems = List.filter (
    fun (fs, fstype) ->
      fstype = "btrfs"
  ) filesystems in
  let btrfs_filesystems = List.map fst btrfs_filesystems in
  let filesystems = List.map fst filesystems in
  let filesystems = List.sort compare filesystems in

  let is_ignored fs =
    let fs = g#canonical_device_name fs in
    List.exists (fun fs' -> fs = g#canonical_device_name fs') ignores
  in

  let is_read_only_lv = is_read_only_lv g in

  let is_readonly_btrfs_snapshot fs mp =
    try
      let is_btrfs = List.mem fs btrfs_filesystems in
      if is_btrfs then (
        try
          let vol_info = g#btrfs_subvolume_show mp in
          String.find (List.assoc "Flags" vol_info) "readonly" <> -1
        with G.Error _ -> false
      ) else false
    with Not_found -> false
  in

  let is_readonly_device mp =
    let statvfs = g#statvfs mp in
    let flags = statvfs.G.flag in
    (* 0x01 is ST_RDONLY in Linux' GNU libc. *)
    flags <> -1_L && (flags &^ 0x1_L) <> 0_L
  in

  List.iter (
    fun fs ->
      if not (is_ignored fs) && not (is_read_only_lv fs) then (
        if List.mem fs zeroes then (
          message (f_"Zeroing %s") fs;

          g#zero_device fs
        ) else (
          let mounted =
            try g#mount fs "/"; true
            with _ -> false in

          if mounted then (
            if is_readonly_btrfs_snapshot fs "/" then (
              info (f_"Skipping %s, as it is a read-only btrfs snapshot.") fs;
            ) else if is_readonly_device "/" then (
              info (f_"Skipping %s, as it is a read-only device.") fs;
            ) else (
              message (f_"Fill free space in %s with zero") fs;
              g#zero_free_space "/"
            )
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
              g#zero_device fs;
              if g#pwrite_device fs header 0L <> 4096 then
                error (f_"pwrite: short write restoring swap partition header")
            )
          )
        );

        g#umount_all ()
      )
  ) filesystems;

  (* Fill unused space in volume groups. *)
  let vgs = g#vgs () in
  let vgs = Array.to_list vgs in
  let vgs = List.sort compare vgs in
  List.iter (
    fun vg ->
      if not (List.mem vg ignores) then (
        let lvname = String.random8 () in
        let lvdev = "/dev/" ^ vg ^ "/" ^ lvname in

        let created =
          try g#lvcreate_free lvname vg 100; true
          with _ -> false in

        if created then (
          message (f_"Fill free space in volgroup %s with zero") vg;

          g#zero_device lvdev;
          g#sync ();
          g#lvremove lvdev
        )
      )
  ) vgs;

  (* Don't need libguestfs now. *)
  g#shutdown ();
  g#close ();

  (* Modify SIGINT handler (set first above) to just exit. *)
  let do_sigint _ = exit 1 in
  Sys.set_signal Sys.sigint (Sys.Signal_handle do_sigint);

  (* Now run qemu-img convert which copies the overlay to the
   * destination and automatically does sparsification.
   *)
  message ("Copy to destination and make sparse");

  let cmd =
    sprintf "qemu-img convert -f qcow2 -O %s%s%s %s %s"
      (quote output_format)
      (if compress then " -c" else "")
      (match option with
      | None -> ""
      | Some option -> " -o " ^ quote option)
      (quote overlaydisk) (quote (qemu_input_filename outdisk)) in
  if shell_command cmd <> 0 then
    error (f_"external command failed: %s") cmd;

  (* Finished. *)
  message (f_"Sparsify operation completed with no errors.");
  if not (quiet ()) then
    info (f_"Before deleting the old disk, carefully check that the target disk boots and works correctly.")
