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
  | `Json -> list_entries_json ~sources index

and list_entries_short index =
  List.iter (
    fun (name, { Index_parser.printable_name = printable_name;
                 arch = arch;
                 hidden = hidden }) ->
      if not hidden then (
        printf "%-24s" name;
        printf " %-10s" arch;
        (match printable_name with
        | None -> ()
        | Some s -> printf " %s" s
        );
        printf "\n"
      )
  ) index

and list_entries_long ~sources index =
  let langs = Languages.languages () in

  List.iter (
    fun (source, key, proxy) ->
      printf (f_"Source URI: %s\n") source;
      (match key with
      | Sigchecker.No_Key -> ()
      | Sigchecker.Fingerprint fp ->
        printf (f_"Fingerprint: %s\n") fp;
      | Sigchecker.KeyFile kf ->
        printf (f_"Key: %s\n") kf;
      );
      printf "\n"
  ) sources;

  List.iter (
    fun (name, { Index_parser.printable_name = printable_name;
                 arch = arch;
                 size = size;
                 compressed_size = compressed_size;
                 notes = notes;
                 aliases = aliases;
                 hidden = hidden }) ->
      if not hidden then (
        printf "%-24s %s\n" "os-version:" name;
        (match printable_name with
        | None -> ()
        | Some name -> printf "%-24s %s\n" (s_"Full name:") name;
        );
        printf "%-24s %s\n" (s_"Architecture:") arch;
        printf "%-24s %s\n" (s_"Minimum/default size:") (human_size size);
        (match compressed_size with
        | None -> ()
        | Some size ->
          printf "%-24s %s\n" (s_"Download size:") (human_size size);
        );
        (match aliases with
        | None -> ()
        | Some l -> printf "%-24s %s\n" (s_"Aliases:")
                      (String.concat " " l);
        );
        let notes = Languages.find_notes langs notes in
        (match notes with
        | notes :: _ ->
          printf "\n";
          printf (f_"Notes:\n\n%s\n") notes
        | [] -> ()
        );
        printf "\n"
      )
  ) index

and list_entries_json ~sources index =
  let trailing_comma index size =
    if index = size - 1 then "" else "," in
  let json_string_of_bool b =
    if b then "true" else "false" in
  let json_string_escape str =
    let res = ref "" in
    for i = 0 to String.length str - 1 do
      res := !res ^ (match str.[i] with
        | '"' -> "\\\""
        | '\\' -> "\\\\"
        | '\b' -> "\\b"
        | '\n' -> "\\n"
        | '\r' -> "\\r"
        | '\t' -> "\\t"
        | c -> String.make 1 c)
    done;
    !res in
  let json_optional_printf_string key = function
    | None -> ()
    | Some str ->
      printf "    \"%s\": \"%s\",\n" key (json_string_escape str) in
  let json_optional_printf_int64 key = function
    | None -> ()
    | Some n ->
      printf "    \"%s\": \"%Ld\",\n" key n in
  let json_optional_printf_stringlist key = function
    | None -> ()
    | Some l ->
      printf "    \"%s\": [" key;
      iteri (
        fun i alias ->
          printf " \"%s\"%s" alias (trailing_comma i (List.length l))
      ) l;
      printf " ],\n" in
  let print_notes = function
    | [] -> ()
    | notes ->
      printf "    \"notes\": {\n";
      iteri (
        fun i (lang, langnotes) ->
          let lang =
            match lang with
            | "" -> "C"
            | x -> x in
          printf "      \"%s\": \"%s\"%s\n"
            (json_string_escape lang) (json_string_escape langnotes)
            (trailing_comma i (List.length notes))
      ) notes;
      printf "    },\n" in

  printf "{\n";
  printf "  \"version\": %d,\n" 1;
  printf "  \"sources\": [\n";
  iteri (
    fun i (source, key, proxy) ->
      printf "  {\n";
      (match key with
      | Sigchecker.No_Key -> ()
      | Sigchecker.Fingerprint fp ->
        printf "    \"fingerprint\": \"%s\",\n" fp;
      | Sigchecker.KeyFile kf ->
        printf "    \"key\": \"%s\",\n" kf;
      );
      printf "    \"uri\": \"%s\"\n" source;
      printf "  }%s\n" (trailing_comma i (List.length sources))
  ) sources;
  printf "  ],\n";
  printf "  \"templates\": [\n";
  iteri (
    fun i (name, { Index_parser.printable_name = printable_name;
                   arch = arch;
                   size = size;
                   compressed_size = compressed_size;
                   notes = notes;
                   aliases = aliases;
                   hidden = hidden }) ->
      printf "  {\n";
      printf "    \"os-version\": \"%s\",\n" name;
      json_optional_printf_string "full-name" printable_name;
      printf "    \"arch\": \"%s\",\n" arch;
      printf "    \"size\": %Ld,\n" size;
      json_optional_printf_int64 "compressed-size" compressed_size;
      print_notes notes;
      json_optional_printf_stringlist "aliases" aliases;
      printf "    \"hidden\": %s\n" (json_string_of_bool hidden);
      printf "  }%s\n" (trailing_comma i (List.length index))
  ) index;
  printf "  ]\n";
 printf "}\n"
