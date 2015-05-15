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

(* Command line argument parsing. *)

open Printf

open Common_gettext.Gettext
open Common_utils

open Utils

type mode_t =
| Mode_copying of string * check_t * bool * string option * string option *
    string option
| Mode_in_place
and check_t = [`Ignore|`Continue|`Warn|`Fail]

let parse_cmdline () =
  let add xs s = xs := s :: !xs in

  let check_tmpdir = ref `Warn in
  let set_check_tmpdir = function
    | "ignore" | "i" -> check_tmpdir := `Ignore
    | "continue" | "cont" | "c" -> check_tmpdir := `Continue
    | "warn" | "warning" | "w" -> check_tmpdir := `Warn
    | "fail" | "f" | "error" -> check_tmpdir := `Fail
    | str ->
      error (f_"--check-tmpdir: unknown argument `%s'") str
  in

  let compress = ref false in
  let convert = ref "" in
  let debug_gc = ref false in
  let format = ref "" in
  let ignores = ref [] in
  let in_place = ref false in
  let machine_readable = ref false in
  let option = ref "" in
  let quiet = ref false in
  let tmp = ref "" in
  let zeroes = ref [] in

  let ditto = " -\"-" in
  let argspec = Arg.align [
    "--check-tmpdir", Arg.String set_check_tmpdir,  "ignore|..." ^ " " ^ s_"Check there is enough space in $TMPDIR";
    "--compress", Arg.Set compress,         " " ^ s_"Compressed output format";
    "--convert", Arg.Set_string convert,    s_"format" ^ " " ^ s_"Format of output disk (default: same as input)";
    "--debug-gc", Arg.Set debug_gc,         " " ^ s_"Debug GC and memory allocations";
    "--format",  Arg.Set_string format,     s_"format" ^ " " ^ s_"Format of input disk";
    "--ignore",  Arg.String (add ignores),  s_"fs" ^ " " ^ s_"Ignore filesystem";
    "--in-place", Arg.Set in_place,         " " ^ s_"Modify the disk image in-place";
    "--inplace", Arg.Set in_place,          ditto;
    "--short-options", Arg.Unit display_short_options, " " ^ s_"List short options";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-o",        Arg.Set_string option,     s_"option" ^ " " ^ s_"Add qemu-img options";
    "-q",        Arg.Set quiet,             " " ^ s_"Quiet output";
    "--quiet",   Arg.Set quiet,             ditto;
    "--tmp",     Arg.Set_string tmp,        s_"block|dir|prebuilt:file" ^ " " ^ s_"Set temporary block device, directory or prebuilt file";
    "-v",        Arg.Unit set_verbose,      " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Unit set_verbose,      ditto;
    "-V",        Arg.Unit print_version_and_exit,
                                            " " ^ s_"Display version and exit";
    "--version", Arg.Unit print_version_and_exit,  ditto;
    "-x",        Arg.Unit set_trace,        " " ^ s_"Enable tracing of libguestfs calls";
    "--zero",    Arg.String (add zeroes),   s_"fs" ^ " " ^ s_"Zero filesystem";
  ] in
  long_options := argspec;
  let disks = ref [] in
  let anon_fun s = disks := s :: !disks in
  let usage_msg =
    sprintf (f_"\
%s: sparsify a virtual machine disk

 virt-sparsify [--options] indisk outdisk

 virt-sparsify [--options] --in-place disk

A short summary of the options is given below.  For detailed help please
read the man page virt-sparsify(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference the rest of the args. *)
  let check_tmpdir = !check_tmpdir in
  let compress = !compress in
  let convert = match !convert with "" -> None | str -> Some str in
  let debug_gc = !debug_gc in
  let format = match !format with "" -> None | str -> Some str in
  let ignores = List.rev !ignores in
  let in_place = !in_place in
  let machine_readable = !machine_readable in
  let option = match !option with "" -> None | str -> Some str in
  let quiet = !quiet in
  let tmp = match !tmp with "" -> None | str -> Some str in
  let zeroes = List.rev !zeroes in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if !disks = [] && machine_readable then (
    printf "virt-sparsify\n";
    printf "linux-swap\n";
    printf "zero\n";
    printf "check-tmpdir\n";
    printf "in-place\n";
    printf "tmp-option\n";
    let g = new Guestfs.guestfs () in
    g#add_drive "/dev/null";
    g#launch ();
    if g#feature_available [| "ntfsprogs"; "ntfs3g" |] then
      printf "ntfs\n";
    if g#feature_available [| "btrfs" |] then
      printf "btrfs\n";
    exit 0
  );

  (* Verify we got exactly 1 or 2 disks, depending on the mode. *)
  let indisk, outdisk =
    match in_place, List.rev !disks with
    | false, [indisk; outdisk] -> indisk, outdisk
    | true, [disk] -> disk, ""
    | _ ->
      error "usage is: %s [--options] indisk outdisk OR %s --in-place disk"
        prog prog in

  (* Simple-minded check that the user isn't trying to use the
   * same disk for input and output.
   *)
  if indisk = outdisk then
    error (f_"you cannot use the same disk image for input and output");

  let indisk =
    if not in_place then (
      (* The input disk must be an absolute path, so we can store the name
       * in the overlay disk.
       *)
      let indisk =
        if not (Filename.is_relative indisk) then
          indisk
        else
          Sys.getcwd () // indisk in

      (* Check the output is not a char special (RHBZ#1056290). *)
      if is_char_device outdisk then
        error (f_"output '%s' cannot be a character device, it must be a regular file")
          outdisk;

      indisk
    )
    else (                              (* --in-place checks *)
      if check_tmpdir <> `Warn then
        error (f_"you cannot use --in-place and --check-tmpdir options together");

      if compress then
        error (f_"you cannot use --in-place and --compress options together");

      if convert <> None then
        error (f_"you cannot use --in-place and --convert options together");

      if option <> None then
        error (f_"you cannot use --in-place and -o options together");

      if tmp <> None then
        error (f_"you cannot use --in-place and --tmp options together");

      indisk
    ) in

  let mode =
    if not in_place then
      Mode_copying (outdisk, check_tmpdir, compress, convert, option, tmp)
    else
      Mode_in_place in

  indisk, debug_gc, format, ignores, machine_readable,
    quiet, zeroes, mode
