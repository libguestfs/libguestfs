(* virt-sparsify
 * Copyright (C) 2011 Red Hat Inc.
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

module G = Guestfs

open Utils

let () = Random.self_init ()

(* Command line argument parsing. *)
let prog = Filename.basename Sys.executable_name

let indisk, outdisk, convert, format, ignores, machine_readable, quiet,
  verbose, trace =
  let display_version () =
    let g = new G.guestfs () in
    let version = g#version () in
    printf "virt-sparsify %Ld.%Ld.%Ld%s\n"
      version.G.major version.G.minor version.G.release version.G.extra;
    exit 0
  in

  let add xs s = xs := s :: !xs in

  let convert = ref "" in
  let format = ref "" in
  let ignores = ref [] in
  let machine_readable = ref false in
  let quiet = ref false in
  let verbose = ref false in
  let trace = ref false in

  let argspec = Arg.align [
    "--convert", Arg.Set_string convert,    "format Format of output disk (default: same as input)";
    "--format",  Arg.Set_string format,     "format Format of input disk";
    "--ignore",  Arg.String (add ignores),  "fs Ignore filesystem";
    "--machine-readable", Arg.Set machine_readable, " Make output machine readable";
    "-q",        Arg.Set quiet,             " Quiet output";
    "--quiet",   Arg.Set quiet,             " -\"-";
    "-v",        Arg.Set verbose,           " Enable debugging messages";
    "--verbose", Arg.Set verbose,           " -\"-";
    "-V",        Arg.Unit display_version,  " Display version and exit";
    "--version", Arg.Unit display_version,  " -\"-";
    "-x",        Arg.Set trace,             " Enable tracing of libguestfs calls";
  ] in
  let disks = ref [] in
  let anon_fun s = disks := s :: !disks in
  let usage_msg =
    sprintf "\
%s: sparsify a virtual machine disk

 virt-sparsify [--options] indisk outdisk

A short summary of the options is given below.  For detailed help please
read the man page virt-sparsify(1).
"
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference the rest of the args. *)
  let convert = match !convert with "" -> None | str -> Some str in
  let format = match !format with "" -> None | str -> Some str in
  let ignores = List.rev !ignores in
  let machine_readable = !machine_readable in
  let quiet = !quiet in
  let verbose = !verbose in
  let trace = !trace in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if !disks = [] && machine_readable then (
    printf "virt-sparsify\n";
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

  (* The input disk must be an absolute path, so we can store the name
   * in the overlay disk.
   *)
  let indisk =
    if not (Filename.is_relative indisk) then
      indisk
    else
      Sys.getcwd () // indisk in

  (* Check indisk filename doesn't contain a comma (limitation of qemu-img). *)
  let contains_comma =
    try ignore (String.index indisk ','); true
    with Not_found -> false in
  if contains_comma then
    error "input filename '%s' contains a comma; qemu-img command line syntax prevents us from using such an image" indisk;

  indisk, outdisk, convert, format, ignores, machine_readable, quiet,
  verbose, trace

let () =
  if not quiet then
    printf "Create overlay file to protect source disk ...\n%!"

(* Create the temporary overlay file. *)
let overlaydisk =
  let tmp = Filename.temp_file "sparsify" ".qcow2" in

  (* Unlink on exit. *)
  at_exit (fun () -> try unlink tmp with _ -> ());

  (* Create it with the indisk as the backing file. *)
  let cmd =
    sprintf "qemu-img create -f qcow2 -o backing_file=%s%s %s > /dev/null"
      (Filename.quote indisk)
      (match format with
      | None -> ""
      | Some fmt -> sprintf ",backing_fmt=%s" (Filename.quote fmt))
      (Filename.quote tmp) in
  if verbose then
    printf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    error "external command failed: %s" cmd;

  tmp

let () =
  if not quiet then
    printf "Examine source disk ...\n%!"

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

(* Write zeroes for non-ignored filesystems that we are able to mount. *)
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
        let mounted =
          try g#mount_options "" fs "/"; true
          with _ -> false in

        if mounted then (
          if not quiet then
            printf "Fill free space in %s with zero ...\n%!" fs;

          (* Choose a random filename, just letters and numbers, in
           * 8.3 format.  This ought to be compatible with any
           * filesystem and not clash with existing files.
           *)
          let filename = "/" ^ string_random8 () ^ ".tmp" in

          (* This command is expected to fail. *)
          (try g#dd "/dev/zero" filename with _ -> ());

          (* Make sure the last part of the file is written to disk. *)
          g#sync ();

          g#rm filename
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
          try g#lvcreate lvname vg 32; true
          with _ -> false in

        if created then (
          if not quiet then
            printf "Fill free space in volgroup %s with zero ...\n%!" vg;

          (* XXX Don't have lvcreate -l 100%FREE.  Fake it. *)
          g#lvresize_free lvdev 100;

          (* This command is expected to fail. *)
          (try g#dd "/dev/zero" lvdev with _ -> ());

           g#sync ();
           g#lvremove lvdev
        )
      )
  ) vgs

(* Don't need libguestfs now. *)
let () =
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
        error "external command failed: %s" cmd
      | WSIGNALED i ->
        error "external command '%s' killed by signal %d" cmd i
      | WSTOPPED i ->
        error "external command '%s' stopped by signal %d" cmd i
      );
      if string_prefix line "QEMU QCOW Image (v2)" then
        "qcow2"
      else
        "raw" (* XXX guess *)

(* Now run qemu-img convert which copies the overlay to the
 * destination and automatically does sparsification.
 *)
let () =
  if not quiet then
    printf "Copy to destination and make sparse ...\n%!";

  let cmd =
    sprintf "qemu-img convert -f qcow2 -O %s %s %s"
      (Filename.quote output_format)
      (Filename.quote overlaydisk) (Filename.quote outdisk) in
  if verbose then
    printf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    error "external command failed: %s" cmd

(* Finished. *)
let () =
  if not quiet then (
    print_newline ();
    wrap "Sparsify operation completed with no errors.  Before deleting the old disk, carefully check that the target disk boots and works correctly.\n";
  );

  exit 0
