(* virt-sparsify
 * Copyright (C) 2011-2018 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext
open Getopt.OptionName

open Utils

type cmdline = {
  indisk : string;
  format : string option;
  ignores : string list;
  zeroes : string list;
  mode : mode_t;
}

and mode_t =
| Mode_copying of
    string * check_t * bool * string option * string option * string option
| Mode_in_place
and check_t = [`Ignore|`Continue|`Warn|`Fail]

let parse_cmdline () =
  let add xs s = List.push_front s xs in

  let check_tmpdir = ref `Warn in
  let set_check_tmpdir = function
    | "ignore" | "i" -> check_tmpdir := `Ignore
    | "continue" | "cont" | "c" -> check_tmpdir := `Continue
    | "warn" | "warning" | "w" -> check_tmpdir := `Warn
    | "fail" | "f" | "error" -> check_tmpdir := `Fail
    | str ->
      error (f_"--check-tmpdir: unknown argument ‘%s’") str
  in

  let compress = ref false in
  let convert = ref "" in
  let format = ref "" in
  let ignores = ref [] in
  let in_place = ref false in
  let option = ref "" in
  let tmp = ref "" in
  let zeroes = ref [] in

  let argspec = [
    [ L"check-tmpdir" ], Getopt.String ("ignore|...", set_check_tmpdir),  s_"Check there is enough space in $TMPDIR";
    [ L"compress" ], Getopt.Set compress,         s_"Compressed output format";
    [ L"convert" ], Getopt.Set_string (s_"format", convert),    s_"Format of output disk (default: same as input)";
    [ L"format" ],  Getopt.Set_string (s_"format", format),     s_"Format of input disk";
    [ L"ignore" ],  Getopt.String (s_"fs", add ignores),  s_"Ignore filesystem";
    [ L"in-place"; L"inplace" ], Getopt.Set in_place,         s_"Modify the disk image in-place";
    [ S 'o' ],        Getopt.Set_string (s_"option", option),     s_"Add qemu-img options";
    [ L"tmp" ],     Getopt.Set_string (s_"block|dir|prebuilt:file", tmp),        s_"Set temporary block device, directory or prebuilt file";
    [ L"zero" ],    Getopt.String (s_"fs", add zeroes),   s_"Zero filesystem";
  ] in
  let disks = ref [] in
  let anon_fun s = List.push_front s disks in
  let usage_msg =
    sprintf (f_"\
%s: sparsify a virtual machine disk

 virt-sparsify [--options] indisk outdisk

 virt-sparsify [--options] --in-place disk

A short summary of the options is given below.  For detailed help please
read the man page virt-sparsify(1).
")
      prog in
  let opthandle = create_standard_options argspec ~anon_fun ~key_opts:true ~machine_readable:true usage_msg in
  Getopt.parse opthandle.getopt;

  (* Dereference the rest of the args. *)
  let check_tmpdir = !check_tmpdir in
  let compress = !compress in
  let convert = match !convert with "" -> None | str -> Some str in
  let disks = List.rev !disks in
  let format = match !format with "" -> None | str -> Some str in
  let ignores = List.rev !ignores in
  let in_place = !in_place in
  let option = match !option with "" -> None | str -> Some str in
  let tmp = match !tmp with "" -> None | str -> Some str in
  let zeroes = List.rev !zeroes in

  (* No arguments and machine-readable mode?  Print out some facts
   * about what this binary supports.
   *)
  if disks = [] && machine_readable () then (
    printf "virt-sparsify\n";
    printf "linux-swap\n";
    printf "zero\n";
    printf "check-tmpdir\n";
    printf "in-place\n";
    printf "tmp-option\n";
    let g = open_guestfs () in
    g#add_drive "/dev/null";
    g#launch ();
    if g#feature_available [| "ntfsprogs"; "ntfs3g" |] then
      printf "ntfs\n";
    if g#feature_available [| "btrfs" |] then
      printf "btrfs\n";
    exit 0
  );

  let indisk, mode =
    if not in_place then (      (* copying mode checks *)
      let indisk, outdisk =
        match disks with
        | [indisk; outdisk] -> indisk, outdisk
        | _ -> error (f_"usage: %s [--options] indisk outdisk") prog in

      (* Simple-minded check that the user isn't trying to use the
       * same disk for input and output.
       *)
      if indisk = outdisk then
        error (f_"you cannot use the same disk image for input and output");

      (* The input disk must be an absolute path, so we can store the name
       * in the overlay disk.
       *)
      let indisk = absolute_path indisk in

      (* Check the output is not a char special (RHBZ#1056290). *)
      if is_char_device outdisk then
        error (f_"output ‘%s’ cannot be a character device, it must be a regular file")
              outdisk;

      indisk,
      Mode_copying (outdisk, check_tmpdir, compress, convert, option, tmp)
    )
    else (                      (* --in-place checks *)
      let indisk =
        match disks with
        | [indisk] -> indisk
        | _ -> error "usage: %s --in-place [--options] indisk" prog in

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

      indisk, Mode_in_place
    ) in

  { indisk = indisk;
    format = format;
    ignores = ignores;
    zeroes = zeroes;
    mode = mode;
  }
