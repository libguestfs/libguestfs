(* virt-builder
 * Copyright (C) 2013-2015 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Utils

open Printf
open Unix

type index = (string * entry) list      (* string = "os-version" *)
and entry = {
  printable_name : string option;       (* the name= field *)
  osinfo : string option;
  file_uri : string;
  arch : string;
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
  proxy : Downloader.proxy_mode;
}

let print_entry chan (name, { printable_name = printable_name;
                              file_uri = file_uri;
                              arch = arch;
                              osinfo = osinfo;
                              signature_uri = signature_uri;
                              checksums = checksums;
                              revision = revision;
                              format = format;
                              size = size;
                              compressed_size = compressed_size;
                              expand = expand;
                              lvexpand = lvexpand;
                              notes = notes;
                              aliases = aliases;
                              hidden = hidden }) =
  let fp fs = fprintf chan fs in
  fp "[%s]\n" name;
  (match printable_name with
  | None -> ()
  | Some name -> fp "name=%s\n" name
  );
  (match osinfo with
  | None -> ()
  | Some id -> fp "osinfo=%s\n" id
  );
  fp "file=%s\n" file_uri;
  fp "arch=%s\n" arch;
  (match signature_uri with
  | None -> ()
  | Some uri -> fp "sig=%s\n" uri
  );
  (match checksums with
  | None -> ()
  | Some checksums ->
    List.iter (
      fun c ->
        fp "checksum[%s]=%s\n"
          (Checksums.string_of_csum_t c) (Checksums.string_of_csum c)
    ) checksums
  );
  fp "revision=%s\n" (string_of_revision revision);
  (match format with
  | None -> ()
  | Some format -> fp "format=%s\n" format
  );
  fp "size=%Ld\n" size;
  (match compressed_size with
  | None -> ()
  | Some size -> fp "compressed_size=%Ld\n" size
  );
  (match expand with
  | None -> ()
  | Some expand -> fp "expand=%s\n" expand
  );
  (match lvexpand with
  | None -> ()
  | Some lvexpand -> fp "lvexpand=%s\n" lvexpand
  );
  List.iter (
    fun (lang, notes) ->
      match lang with
      | "" -> fp "notes=%s\n" notes
      | lang -> fp "notes[%s]=%s\n" lang notes
  ) notes;
  (match aliases with
  | None -> ()
  | Some l -> fp "aliases=%s\n" (String.concat " " l)
  );
  if hidden then fp "hidden=true\n"
