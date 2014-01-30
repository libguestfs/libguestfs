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

let split_locale loc =
  let regex = Str.regexp "^\\([A-Za-z]+\\)\\(_\\([A-Za-z]+\\)\\)?\\(\\.\\([A-Za-z0-9-]+\\)\\)?\\(@\\([A-Za-z]+\\)\\)?$" in
  let l = ref [] in
  if Str.string_match regex loc 0 then (
    let match_or_empty n =
      try Str.matched_group n loc with
      | Not_found -> ""
    in
    let lang = Str.matched_group 1 loc in
    let territory = match_or_empty 3 in
    (match territory with
    | "" -> ()
    | territory -> l := (lang ^ "_" ^ territory) :: !l);
    l := lang :: !l;
  );
  l := "" :: !l;
  List.rev !l

let rec list_entries ~list_format ~sources index =
  match list_format with
  | `Short -> list_entries_short index
  | `Long -> list_entries_long ~sources index
  | `Json -> list_entries_json ~sources index

and list_entries_short index =
  List.iter (
    fun (name, { Index_parser.printable_name = printable_name;
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
  let langs = match Setlocale.setlocale Setlocale.LC_MESSAGES None with
  | None -> [""]
  | Some locale -> split_locale locale in

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
        let notes = List.fold_left (
          fun acc lang ->
            let res = List.filter (
              fun (langkey, _) ->
                match langkey with
                | "C" -> lang = ""
                | langkey -> langkey = lang
            ) notes in
            match res with
            | (_, noteskey) :: _ -> noteskey :: acc
            | [] -> acc
        ) [] langs in
        let notes = List.rev notes in
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
    fun i (source, fingerprint) ->
      printf "  {\n";
      printf "    \"uri\": \"%s\",\n" source;
      printf "    \"fingerprint\": \"%s\"\n" fingerprint;
      printf "  }%s\n" (trailing_comma i (List.length sources))
  ) sources;
  printf "  ],\n";
  printf "  \"templates\": [\n";
  iteri (
    fun i (name, { Index_parser.printable_name = printable_name;
                   size = size;
                   compressed_size = compressed_size;
                   notes = notes;
                   hidden = hidden }) ->
      printf "  {\n";
      printf "    \"os-version\": \"%s\",\n" name;
      json_optional_printf_string "full-name" printable_name;
      printf "    \"size\": %Ld,\n" size;
      json_optional_printf_int64 "compressed-size" compressed_size;
      print_notes notes;
      printf "    \"hidden\": %s\n" (json_string_of_bool hidden);
      printf "  }%s\n" (trailing_comma i (List.length index))
  ) index;
  printf "  ]\n";
 printf "}\n"
