(* virt-builder
 * Copyright (C) 2013-2019 Red Hat Inc.
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

let re_locale =
  PCRE.compile ~caseless:true "^([a-z]+)(_([a-z]+))?(\\.([a-z0-9-]+))?(@([a-z]+))?$"

let split_locale loc =
  let l = ref [] in
  if PCRE.matches re_locale loc then (
    let match_or_empty n = try PCRE.sub n with Not_found -> "" in
    let lang = PCRE.sub 1 in
    let territory = match_or_empty 3 in
    (match territory with
    | "" -> ()
    | territory -> List.push_front (lang ^ "_" ^ territory) l);
    List.push_front lang l;
  );
  List.push_front "" l;
  List.rev !l

let languages () =
  match Setlocale.setlocale Setlocale.LC_MESSAGES None with
  | None -> [""]
  | Some locale -> split_locale locale

let find_notes languages notes =
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
  ) [] languages in
  List.rev notes
