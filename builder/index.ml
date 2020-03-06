(* virt-builder
 * Copyright (C) 2013-2020 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Utils

open Printf
open Unix

type index = (string * entry) list      (* string = "os-version" *)
and entry = {
  printable_name : string option;       (* the name= field *)
  osinfo : string option;
  file_uri : string;
  arch : arch;
  signature_uri : string option;        (* deprecated, will be removed in 1.26 *)
  checksums : Checksums.csum_t list option;
  revision : Utils.revision;
  format : string option;
  size : int64;
  compressed_size : int64 option;
  expand : string option;
  lvexpand : string option;
  notes : (string * string) list;
  hidden : bool;
  aliases : string list option;

  sigchecker : Sigchecker.t;
  proxy : Curl.proxy;
}
and arch =
  | Arch of string
  | GuessedArch of string

let string_of_arch = function Arch a | GuessedArch a -> a

let print_entry chan (name, { printable_name; file_uri; arch; osinfo;
                              signature_uri; checksums; revision; format;
                              size; compressed_size; expand; lvexpand;
                              notes; aliases; hidden }) =
  let fp fs = fprintf chan fs in
  fp "[%s]\n" name;
  Option.may (fp "name=%s\n") printable_name;
  Option.may (fp "osinfo=%s\n") osinfo;
  fp "file=%s\n" file_uri;
  fp "arch=%s\n" (string_of_arch arch);
  Option.may (fp "sig=%s\n") signature_uri;
  Option.may (
    List.iter (
      fun c ->
        fp "checksum[%s]=%s\n"
          (Checksums.string_of_csum_t c) (Checksums.string_of_csum c)
    )
  ) checksums;
  fp "revision=%s\n" (string_of_revision revision);
  Option.may (fp "format=%s\n") format;
  fp "size=%Ld\n" size;
  Option.may (fp "compressed_size=%Ld\n") compressed_size;
  Option.may (fp "expand=%s\n") expand;
  Option.may (fp "lvexpand=%s\n") lvexpand;
  List.iter (
    fun (lang, notes) ->
      match lang with
      | "" -> fp "notes=%s\n" notes
      | lang -> fp "notes[%s]=%s\n" lang notes
  ) notes;
  Option.may (fun l -> fp "aliases=%s\n" (String.concat " " l)) aliases;
  if hidden then fp "hidden=true\n"
