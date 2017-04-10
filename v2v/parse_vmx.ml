(* virt-v2v
 * Copyright (C) 2017 Red Hat Inc.
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

open Printf

open Common_utils
open Common_gettext.Gettext

(* As far as I can tell the VMX format is totally unspecified.
 * However libvirt has a useful selection of .vmx files in the
 * sources which explore some of the darker regions of this
 * format.
 *
 * So here are some facts about VMX derived from libvirt and
 * other places:
 *
 * - Keys are compared case insensitively.  We assume here
 *   that keys are 7-bit ASCII.
 *
 * - Multiple keys with the same name are not allowed.
 *
 * - Escaping in the value string is possible using a very weird
 *   escape format: "|22" means the character '\x22'.  To write
 *   a pipe character you must use "|7C".
 *
 * - Boolean values are written "TRUE", "FALSE", "True", "true", etc.
 *   Because of the quotes they cannot be distinguished from strings.
 *
 * - Comments (#...) and blank lines are ignored.  Some files start
 *   with a hash-bang path, but we ignore those as comments.  This
 *   parser also ignores any other line which it doesn't understand,
 *   but will print a warning.
 *
 * - Multi-line values are not permitted.
 *
 * - Keys are namespaced using dots, eg. scsi0:0.deviceType has
 *   the namespace "scsi0:0" and the key name "deviceType".
 *
 * - Using namespace.present = "FALSE" means that all other keys
 *   in and under the namespace are ignored.
 *
 * - You cannot have a namespace and a key with the same name, eg.
 *   this is not allowed:
 *     namespace = "some value"
 *     namespace.foo = "another value"
 *
 * - The Hashicorp packer VMX writer considers some special keys
 *   as not requiring any quotes around their values, but I'm
 *   ignoring that for now.
 *)

(* This VMX file:
 *
 *   foo.a = "abc"
 *   foo.b = "def"
 *   foo.bar.c = "abc"
 *   foo.bar.d = "def"
 *
 * would be represented by this structure:
 *
 *   "foo" => Namespace (             # "foo" is a namespace
 *              "a" => Key "abc";     # "foo.a" is a key with value "abc"
 *              "b" => Key "def";
 *              "bar" => Namespace (  # "foo.bar" is another namespace
 *                         "c" => Key "abc";
 *                         "d" => Key "def";
 *                       )
 *            )
 *   ‘( => )’s represent the StringMap type.
 *)
type t = key StringMap.t

and key =
  | Key of string
  | Namespace of t

let empty = StringMap.empty

(* Compare two trees for equality. *)
let rec equal vmx1 vmx2 =
  let cmp k1 k2 =
    match k1, k2 with
    | Key v1, Key v2 -> v1 = v2
    | Key _, Namespace _ -> false
    | Namespace _, Key _ -> false
    | Namespace vmx1, Namespace vmx2 -> equal vmx1 vmx2
  in
  StringMap.equal cmp vmx1 vmx2

(* Higher-order functions. *)
let rec select_namespaces pred vmx =
  _select_namespaces [] pred vmx

and _select_namespaces path pred vmx =
  StringMap.fold (
    fun k v new_vmx ->
      let path = path @ [k] in
      match v with
      | Key _ -> new_vmx
      | Namespace _ when pred path ->
         StringMap.add k v new_vmx
      | Namespace t ->
         let t = _select_namespaces path pred t in
         if not (equal t empty) then
           StringMap.add k (Namespace t) new_vmx
         else
           new_vmx
  ) vmx empty

let rec map f vmx =
  _map [] f vmx

and _map path f vmx =
  StringMap.fold (
    fun k v r ->
      let path = path @ [k] in
      match v with
      | Key v -> r @ [ f path (Some v) ]
      | Namespace t -> r @ [ f path None ] @ _map path f t
  ) vmx []

let rec namespace_present vmx = function
  | [] -> false
  | [ns] ->
     let ns = String.lowercase_ascii ns in
     (try
        let v = StringMap.find ns vmx in
        match v with
        | Key _ -> false
        | Namespace _ -> true
      with
        Not_found -> false
     )
  | ns :: path ->
     let ns = String.lowercase_ascii ns in
     (try
        let v = StringMap.find ns vmx in
        match v with
        | Key _ -> false
        | Namespace vmx -> namespace_present vmx path
      with
        Not_found -> false
     )

(* Dump the vmx structure to [chan].  Used for debugging. *)
let rec print chan indent vmx =
  StringMap.iter (print_key chan indent) vmx

and print_key chan indent k = function
  | Key v ->
     output_spaces chan indent;
     fprintf chan "%s = \"%s\"\n" k v
  | Namespace vmx ->
     output_spaces chan indent;
     fprintf chan "namespace '%s':\n" k;
     print chan (indent+4) vmx

(* As above, but creates a string instead. *)
let rec to_string indent vmx =
  StringMap.fold (fun k v str -> str ^ to_string_key indent k v) vmx ""

and to_string_key indent k = function
  | Key v ->
     String.spaces indent ^ sprintf "%s = \"%s\"\n" k v
  | Namespace vmx ->
     String.spaces indent ^ sprintf "namespace '%s':\n" k ^
       to_string (indent+4) vmx

(* Access keys in the tree. *)
let rec get_string vmx = function
  | [] -> None
  | [k] ->
     let k = String.lowercase_ascii k in
     (try
        let v = StringMap.find k vmx in
        match v with
        | Key v -> Some v
        | Namespace _ -> None
      with Not_found -> None
     )
  | ns :: path ->
     let ns = String.lowercase_ascii ns in
     (try
        let v = StringMap.find ns vmx in
        match v with
        | Key v -> None
        | Namespace vmx -> get_string vmx path
      with
        Not_found -> None
     )

let get_int64 vmx path =
  match get_string vmx path with
  | None -> None
  | Some i -> Some (Int64.of_string i)

let get_int vmx path =
  match get_string vmx path with
  | None -> None
  | Some i -> Some (int_of_string i)

let rec get_bool vmx path =
  match get_string vmx path with
  | None -> None
  | Some t -> Some (vmx_bool_of_string t)

and vmx_bool_of_string t =
  if String.lowercase_ascii t = "true" then true
  else if String.lowercase_ascii t = "false" then false
  else failwith "bool_of_string"

(* Regular expression used to match key = "value" in VMX file. *)
let rex = Str.regexp "^\\([^ \t=]+\\)[ \t]*=[ \t]*\"\\(.*\\)\"$"

(* Remove the weird escapes used in value strings.  See description above. *)
let remove_vmx_escapes str =
  let len = String.length str in
  let out = Bytes.make len '\000' in
  let j = ref 0 in

  let rec loop i =
    if i >= len then ()
    else (
      let c = String.unsafe_get str i in
      if i <= len-3 && c = '|' then (
        let c1 = str.[i+1] and c2 = str.[i+2] in
        if Char.isxdigit c1 && Char.isxdigit c2 then (
          let x = Char.hexdigit c1 * 0x10 + Char.hexdigit c2 in
          Bytes.set out !j (Char.chr x);
          incr j;
          loop (i+3)
        )
        else (
          Bytes.set out !j c;
          incr j;
          loop (i+1)
        )
      )
      else (
        Bytes.set out !j c;
        incr j;
        loop (i+1)
      )
    )
  in
  loop 0;

  (* Truncate the output string to its real size and return it
   * as an immutable string.
   *)
  Bytes.sub_string out 0 !j

(* Parsing. *)
let rec parse_file vmx_filename =
  (* Read the whole file as a list of lines. *)
  let str = read_whole_file vmx_filename in
  if verbose () then eprintf "VMX file:\n%s\n" str;
  parse_string str

and parse_string str =
  let lines = String.nsplit "\n" str in

  (* I've never seen any VMX file with CR-LF endings, and VMware
   * itself is Linux-based, but to be on the safe side ...
   *)
  let lines = List.map (String.trimr ~test:((=) '\r')) lines in

  (* Ignore blank lines and comments. *)
  let lines = List.filter (
    fun line ->
      let line = String.triml line in
      let len = String.length line in
      len > 0 && line.[0] != '#'
  ) lines in

  (* Parse the lines into key = "value". *)
  let lines = filter_map (
    fun line ->
      if Str.string_match rex line 0 then (
        let key = Str.matched_group 1 line in
        let key = String.lowercase_ascii key in
        let value = Str.matched_group 2 line in
        let value = remove_vmx_escapes value in
        Some (key, value)
      )
      else (
        warning (f_"vmx parser: cannot parse this line, ignoring: %s") line;
        None
      )
  ) lines in

  (* Split the keys into namespace paths. *)
  let lines =
    List.map (fun (key, value) -> String.nsplit "." key, value) lines in

  (* Build a tree from the flat list and return it.  This is horribly
   * inefficient, at least O(n²), possibly even O(n².log n).  Hope
   * there are no large VMX files!  (XXX)
   *)
  let vmx =
    List.fold_left (
      fun vmx (path, value) -> insert vmx value path
    ) empty lines in

  (* If we're verbose, dump the parsed VMX for debugging purposes. *)
  if verbose () then (
    eprintf "parsed VMX tree:\n";
    print stderr 0 vmx
  );

  (* Drop all present = "FALSE" namespaces. *)
  let vmx = drop_not_present vmx in

  vmx

and insert vmx value = function
  | [] -> assert false
  | [k] ->
     if StringMap.mem k vmx then (
       warning (f_"vmx parser: duplicate key '%s' ignored") k;
       vmx
     ) else
       StringMap.add k (Key value) vmx
  | ns :: path ->
     let v =
       try
         (match StringMap.find ns vmx with
          | Namespace vmx -> Some vmx
          | Key _ -> None
         )
       with Not_found -> None in
     let v =
       match v with
       | None ->
          (* Completely new namespace. *)
          insert empty value path
       | Some v ->
          (* Insert the subkey into the previously created namespace. *)
          insert v value path in
     StringMap.add ns (Namespace v) vmx

(* Find any "present" keys.  If we find present = "FALSE", then
 * drop the containing namespace and all subkeys and subnamespaces.
 *)
and drop_not_present vmx =
  StringMap.fold (
    fun k v new_vmx ->
      match v with
      | Key _ ->
         StringMap.add k v new_vmx
      | Namespace vmx when contains_key_present_false vmx ->
         (* drop this namespace and all sub-spaces *)
         new_vmx
      | Namespace v ->
         (* recurse into sub-namespace and do the same check *)
         let v = drop_not_present v in
         StringMap.add k (Namespace v) new_vmx
  ) vmx empty

and contains_key_present_false vmx =
  try
    match StringMap.find "present" vmx with
    | Key v when vmx_bool_of_string v = false -> true
    | Key _ | Namespace _ -> false
  with
    Failure _ | Not_found -> false
