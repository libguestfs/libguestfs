(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

(* Parsing and handling of elements. *)

open Common_gettext.Gettext
open Common_utils

open Utils

open Printf

module StringSet = Set.Make (String)

type element = {
  directory : string;
  hooks : hooks_map;
}
and hooks_map = (string, string list) Hashtbl.t  (* hook name, scripts *)

exception Duplicate_script of string * string (* hook, script *)

(* These are the elements which we don't ever try to use. *)
let builtin_elements_blacklist = [
]

(* These are the scripts which we don't ever try to run.
 * Usual reason could be that they are not compatible the way virt-dib works:
 * e.g. they expect the tree of elements outside the chroot, which is not
 * available in the appliance. *)
let builtin_scripts_blacklist = [
  "01-sahara-version";            (* Gets the Git commit ID of the d-i-b and
                                   * sahara-image-elements repositories. *)
]

let valid_script_name n =
  let is_char_valid = function
    | 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' | '-' -> true
    | _ -> false in
  try ignore (string_index_fn (fun c -> not (is_char_valid c)) n); false
  with Not_found -> true

let stringset_of_list l =
  List.fold_left (fun acc x -> StringSet.add x acc) StringSet.empty l

let load_hooks ~debug path =
  let hooks = Hashtbl.create 13 in
  let entries = Array.to_list (Sys.readdir path) in
  let entries = List.filter (fun x -> Filename.check_suffix x ".d") entries in
  let entries = List.map (fun x -> (x, path // x)) entries in
  let entries = List.filter (fun (_, x) -> is_directory x) entries in
  List.iter (
    fun (hook, p) ->
      let listing = Array.to_list (Sys.readdir p) in
      let scripts = List.filter valid_script_name listing in
      let scripts = List.filter (
        fun x ->
          try
            let s = Unix.stat (p // x) in
            s.Unix.st_kind = Unix.S_REG && s.Unix.st_perm land 0o111 > 0
          with Unix.Unix_error _ -> false
      ) scripts in
      if scripts <> [] then
        Hashtbl.add hooks hook scripts
  ) entries;
  hooks

let load_scripts (g : Guestfs.guestfs) path =
  let listing = Array.to_list (g#readdir path) in
  let scripts = List.filter (
    function
    | { Guestfs.ftyp = ('r'|'l'|'u'|'?') } -> true
    | _ -> false
    ) listing in
  let scripts = List.filter (fun x -> valid_script_name x.Guestfs.name) scripts in
  filter_map (
     fun x ->
       let { Guestfs.st_mode = mode } = g#statns (path ^ "/" ^ x.Guestfs.name) in
       if mode &^ 0o111_L > 0_L then Some x.Guestfs.name
       else None
   ) scripts

let load_elements ~debug paths =
  let loaded_elements = Hashtbl.create 13 in
  let paths = List.filter is_directory paths in
  List.iter (
    fun path ->
      let listing = Array.to_list (Sys.readdir path) in
      let listing = List.map (fun x -> (x, path // x)) listing in
      let listing = List.filter (fun (_, x) -> is_directory x) listing in
      List.iter (
        fun (p, dir) ->
          if not (Hashtbl.mem loaded_elements p) then (
            let elem = { directory = dir; hooks = load_hooks ~debug dir } in
            Hashtbl.add loaded_elements p elem
          ) else if debug >= 1 then (
            printf "element %s (in %s) already present" p path;
          )
      ) listing
  ) paths;
  loaded_elements

let load_dependencies elements loaded_elements =
  let get filename element =
    try
      let path = (Hashtbl.find loaded_elements element).directory in
      let path = path // filename in
      if Sys.file_exists path then (
        let lines = read_whole_file path in
        let lines = String.nsplit "\n" lines in
        let lines = List.filter ((<>) "") lines in
        stringset_of_list lines
      ) else
        StringSet.empty
    with Not_found ->
      error (f_"element %s not found") element in
  let get_deps = get "element-deps" in
  let get_provides = get "element-provides" in

  let queue = Queue.create () in
  let final = ref StringSet.empty in
  let provided = ref StringSet.empty in
  let provided_by = Hashtbl.create 13 in
  List.iter (fun x -> Queue.push x queue) elements;
  final := stringset_of_list elements;
  while not (Queue.is_empty queue) do
    let elem = Queue.pop queue in
    if StringSet.mem elem !provided <> true then (
      let element_deps = get_deps elem in
      let element_provides = get_provides elem in
      (* Save which elements provide another element for potential
       * error message.
       *)
      StringSet.iter (fun x -> Hashtbl.add provided_by x elem) element_provides;
      provided := StringSet.union !provided element_provides;
      StringSet.iter (fun x -> Queue.push x queue)
        (StringSet.diff element_deps (StringSet.union !final !provided));
      final := StringSet.union !final element_deps
    )
  done;
  let conflicts = StringSet.inter (stringset_of_list elements) !provided in
  if not (StringSet.is_empty conflicts) then (
    let buf = Buffer.create 100 in
    StringSet.iter (
      fun elem ->
        let s = sprintf (f_"  %s: already provided by %s")
                  elem (Hashtbl.find provided_by elem) in
        Buffer.add_string buf s
    ) conflicts;
    error (f_"following elements are already provided by another element:\n%s")
      (Buffer.contents buf)
  );
  if not (StringSet.mem "operating-system" !provided) then
    error (f_"please include an operating system element");
  StringSet.diff !final !provided

let copy_element element destdir blacklist =
  let entries = Array.to_list (Sys.readdir element.directory) in
  let entries = List.filter ((<>) "tests") entries in
  let entries = List.filter ((<>) "test-elements") entries in
  let dirs, nondirs = List.partition is_directory entries in
  let dirs = List.map (fun x -> (x, element.directory // x, destdir // x)) dirs in
  let nondirs = List.map (fun x -> element.directory // x) nondirs in
  List.iter (
    fun (e, path, destpath) ->
      do_mkdir destpath;
      let subentries = Array.to_list (Sys.readdir path) in
      let subentries = List.filter (not_in_list blacklist) subentries in
      List.iter (
        fun sube ->
          if is_regular_file (destpath // sube) then (
            raise (Duplicate_script (e, sube))
          ) else
            do_cp (path // sube) destpath
      ) subentries;
  ) dirs;
  List.iter (
    fun path ->
      do_cp path destdir
  ) nondirs

let copy_elements elements loaded_elements blacklist destdir =
  do_mkdir destdir;
  StringSet.iter (
    fun element ->
      try
        copy_element (Hashtbl.find loaded_elements element) destdir blacklist
      with
      | Duplicate_script (hook, script) ->
        let element_has_script e =
          try
            let s = Hashtbl.find (Hashtbl.find loaded_elements e).hooks hook in
            List.exists ((=) script) s
          with Not_found -> false in
        let dups = StringSet.filter element_has_script elements in
        error (f_"There is a duplicated script in your elements:\n%s/%s in: %s")
          hook script (String.concat " " (StringSet.elements dups))
  ) elements
