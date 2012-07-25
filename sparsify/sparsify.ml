(* virt-sparsify
 * Copyright (C) 2011-2012 Red Hat Inc.
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

open Unix
open Printf

open Sparsify_gettext.Gettext

module G = Guestfs

open Utils

let () = Random.self_init ()

(* Command line argument parsing. *)
let prog = Filename.basename Sys.executable_name

let indisk, outdisk, compress, convert, debug_gc,
  format, ignores, machine_readable,
  option, quiet, verbose, trace, zeroes =
  let display_version () =
    let g = new G.guestfs () in
    let version = g#version () in
    printf "virt-sparsify %Ld.%Ld.%Ld%s\n"
      version.G.major version.G.minor version.G.release version.G.extra;
    exit 0
  in

  let add xs s = xs := s :: !xs in

  let compress = ref false in
  let convert = ref "" in
  let debug_gc = ref false in
  let format = ref "" in
  let ignores = ref [] in
  let machine_readable = ref false in
  let option = ref "" in
  let quiet = ref false in
  let verbose = ref false in
  let trace = ref false in
  let zeroes = ref [] in

  let argspec = Arg.align [
    "--compress", Arg.Set compress,         " " ^ s_"Compressed output format";
    "--convert", Arg.Set_string convert,    s_"format" ^ " " ^ s_"Format of output disk (default: same as input)";
    "--debug-gc", Arg.Set debug_gc,         " " ^ s_"Debug GC and memory allocations";
    "--format",  Arg.Set_string format,     s_"format" ^ " " ^ s_"Format of input disk";
    "--ignore",  Arg.String (add ignores),  s_"fs" ^ " " ^ s_"Ignore filesystem";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-o",        Arg.Set_string option,     s_"option" ^ " " ^ s_"Add qemu-img options";
    "-q",        Arg.Set quiet,             " " ^ s_"Quiet output";
    "--quiet",   Arg.Set quiet,             " -\"-";
    "-v",        Arg.Set verbose,           " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set verbose,           " -\"-";
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  " -\"-";
    "-x",        Arg.Set trace,             " " ^ s_"Enable tracing of libguestfs calls";
    "--zero",    Arg.String (add zeroes),   s_"fs" ^ " " ^ s_"Zero filesystem";
  ] in
  let disks = ref [] in
  let anon_fun s = disks := s :: !disks in
  let usage_msg =
    sprintf (f_"\
%s: sparsify a virtual machine disk

 virt-sparsify [--options] indisk outdisk

A short summary of the options is given below.  For detailed help please
read the man page virt-sparsify(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference the rest of the args. *)
  let compress = !compress in
  let convert = match !convert with "" -> None | str -> Some str in
  let debug_gc = !debug_gc in
  let format = match !format with "" -> None | str -> Some str in
  let ignores = List.rev !ignores in
  let machine_readable = !machine_readable in
  let option = match !option with "" -> None | str -> Some str in
  let quiet = !quiet in
  let verbose = !verbose in
  let trace = !trace in
  let zeroes = List.rev !zeroes in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if !disks = [] && machine_readable then (
    printf "virt-sparsify\n";
    printf "linux-swap\n";
    printf "zero\n";
    let g = new G.guestfs () in
    g#add_drive_opts "/dev/null";
    g#launch ();
    if feature_available g [| "ntfsprogs"; "ntfs3g" |] then
      printf "ntfs\n";
    if feature_available g [| "btrfs" |] then
      printf "btrfs\n";
    exit 0
  );

  (* Verify we got exactly 2 disks. *)
  let indisk, outdisk =
    match List.rev !disks with
    | [indisk; outdisk] -> indisk, outdisk
    | _ ->
        error "usage is: %s [--options] indisk outdisk" prog in

  (* Simple-minded check that the user isn't trying to use the
   * same disk for input and output.
   *)
  if indisk = outdisk then
    error (f_"you cannot use the same disk image for input and output");

  (* The input disk must be an absolute path, so we can store the name
   * in the overlay disk.
   *)
  let indisk =
    if not (Filename.is_relative indisk) then
      indisk
    else
      Sys.getcwd () // indisk in

  let contains_colon filename =
    try ignore (String.index filename ':'); true with Not_found -> false in

  (* Check filenames don't contain a colon (limitation of qemu-img). *)
  if contains_colon indisk then
    error (f_"input filename '%s' contains a colon (':'); qemu-img command line syntax prevents us from using such an image") indisk;

  if contains_colon outdisk then
    error (f_"output filename '%s' contains a colon (':'); qemu-img command line syntax prevents us from using such an image") outdisk;

  indisk, outdisk, compress, convert,
    debug_gc, format, ignores, machine_readable,
    option, quiet, verbose, trace, zeroes

let () =
  if not quiet then
    printf (f_"Create overlay file to protect source disk ...\n%!")

(* Create the temporary overlay file. *)
let overlaydisk =
  let tmp = Filename.temp_file "sparsify" ".qcow2" in
  let unlink_tmp () = try unlink tmp with _ -> () in

  (* Unlink on exit. *)
  at_exit unlink_tmp;

  (* Unlink on sigint. *)
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> unlink_tmp ()));

  (* Create it with the indisk as the backing file. *)
  let cmd =
    let options =
      let backing_file_option =
        [sprintf "backing_file=%s" (replace_str indisk "," ",,")] in
      let backing_fmt_option =
        match format with
        | None -> []
        | Some fmt -> [sprintf "backing_fmt=%s" fmt] in
      backing_file_option @ backing_fmt_option in
    sprintf "qemu-img create -f qcow2 -o %s %s > /dev/null"
      (Filename.quote (String.concat "," options)) (Filename.quote tmp) in
  if verbose then
    printf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    error (f_"external command failed: %s") cmd;

  tmp

let () =
  if not quiet then
    printf (f_"Examine source disk ...\n%!")

(* Connect to libguestfs. *)
let g =
  let g = new G.guestfs () in
  if trace then g#set_trace true;
  if verbose then g#set_verbose true;

  (* Note that the temporary overlay disk is always qcow2 format. *)
  g#add_drive_opts ~format:"qcow2" ~readonly:false overlaydisk;

  if not quiet then Progress.set_up_progress_bar ~machine_readable g;
  g#launch ();

  g

(* Get the size in bytes of the input disk. *)
let insize = g#blockdev_getsize64 "/dev/sda"

(* Write zeroes for non-ignored filesystems that we are able to mount,
 * and selected swap partitions.
 *)
let () =
  let filesystems = g#list_filesystems () in
  let filesystems = List.map fst filesystems in
  let filesystems = List.sort compare filesystems in

  let is_ignored fs =
    let fs = canonicalize fs in
    List.exists (fun fs' -> fs = canonicalize fs') ignores
  in

  List.iter (
    fun fs ->
      if not (is_ignored fs) then (
        if List.mem fs zeroes then (
          if not quiet then
            printf (f_"Zeroing %s ...\n%!") fs;

          g#zero_device fs
        ) else (
          let mounted =
            try g#mount_options "" fs "/"; true
            with _ -> false in

          if mounted then (
            if not quiet then
              printf (f_"Fill free space in %s with zero ...\n%!") fs;

            g#zero_free_space "/"
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
              if not quiet then
                printf (f_"Clearing Linux swap on %s ...\n%!") fs;

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
  ) filesystems

(* Fill unused space in volume groups. *)
let () =
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
          if not quiet then
            printf (f_"Fill free space in volgroup %s with zero ...\n%!") vg;

          g#zero_device lvdev;
          g#sync ();
          g#lvremove lvdev
        )
      )
  ) vgs

(* Don't need libguestfs now. *)
let () =
  g#shutdown ();
  g#close ()

(* What should the output format be?  If the user specified an
 * input format, use that, else detect it from the source image.
 *)
let output_format =
  match convert with
  | Some fmt -> fmt             (* user specified output conversion *)
  | None ->
    match format with
    | Some fmt -> fmt           (* user specified input format, use that *)
    | None ->
      (* Don't know, so we must autodetect. *)
      let cmd = sprintf "file -bsL %s" (Filename.quote indisk) in
      let chan = open_process_in cmd in
      let line = input_line chan in
      let stat = close_process_in chan in
      (match stat with
      | WEXITED 0 -> ()
      | WEXITED _ ->
        error (f_"external command failed: %s") cmd
      | WSIGNALED i ->
        error (f_"external command '%s' killed by signal %d") cmd i
      | WSTOPPED i ->
        error (f_"external command '%s' stopped by signal %d") cmd i
      );
      if string_prefix line "QEMU QCOW Image (v2)" then
        "qcow2"
      else if string_find line "VirtualBox" >= 0 then
        "vdi"
      else
        "raw" (* XXX guess *)

(* Now run qemu-img convert which copies the overlay to the
 * destination and automatically does sparsification.
 *)
let () =
  if not quiet then
    printf (f_"Copy to destination and make sparse ...\n%!");

  let cmd =
    sprintf "qemu-img convert -f qcow2 -O %s%s%s %s %s"
      (Filename.quote output_format)
      (if compress then " -c" else "")
      (match option with
      | None -> ""
      | Some option -> " -o " ^ Filename.quote option)
      (Filename.quote overlaydisk) (Filename.quote outdisk) in
  if verbose then
    printf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    error (f_"external command failed: %s") cmd

(* Finished. *)
let () =
  if not quiet then (
    print_newline ();
    wrap (s_"Sparsify operation completed with no errors.  Before deleting the old disk, carefully check that the target disk boots and works correctly.\n");
  );

  if debug_gc then
    Gc.compact ();

  exit 0
