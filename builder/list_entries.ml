(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

open Printf

let rec list_entries ~list_format ~sources index =
  match list_format with
  | `Short -> list_entries_short index
  | `Long -> list_entries_long ~sources index

and list_entries_short index =
  List.iter (
    fun (name, { Index_parser.printable_name = printable_name;
                 size = size;
                 compressed_size = compressed_size;
                 notes = notes;
                 hidden = hidden }) ->
      if not hidden then (
        printf "%-24s" name;
        (match printable_name with
        | None -> ()
        | Some s -> printf " %s" s
        );
        printf "\n"
      )
  ) index

and list_entries_long ~sources index =
  List.iter (
    fun (source, fingerprint) ->
      printf (f_"Source URI: %s\n") source;
      printf (f_"Fingerprint: %s\n") fingerprint;
      printf "\n"
  ) sources;

  List.iter (
    fun (name, { Index_parser.printable_name = printable_name;
                 size = size;
                 compressed_size = compressed_size;
                 notes = notes;
                 hidden = hidden }) ->
      if not hidden then (
        printf "%-24s %s\n" "os-version:" name;
        (match printable_name with
        | None -> ()
        | Some name -> printf "%-24s %s\n" (s_"Full name:") name;
        );
        printf "%-24s %s\n" (s_"Minimum/default size:") (human_size size);
        (match compressed_size with
        | None -> ()
        | Some size ->
          printf "%-24s %s\n" (s_"Download size:") (human_size size);
        );
        (match notes with
        | None -> ()
        | Some notes ->
          printf "\n";
          printf (f_"Notes:\n\n%s\n") notes
        );
        printf "\n"
      )
  ) index
