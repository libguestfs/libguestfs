(* libguestfs
 * Copyright (C) 2009-2018 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

(* Useful functions.
 * Note we don't want to use any external OCaml libraries which
 * makes this a bit harder than it should be.
 *)

open Std_utils

open Unix
open Printf

open Types

let errcode_of_ret = function
  | RConstOptString _ ->
      `CannotReturnError
  | RErr | RInt _ | RBool _ | RInt64 _ ->
      `ErrorIsMinusOne
  | RConstString _
  | RString _ | RBufferOut _
  | RStringList _ | RHashtable _
  | RStruct _ | RStructList _ ->
      `ErrorIsNULL

let string_of_errcode = function
  | `ErrorIsMinusOne -> "-1"
  | `ErrorIsNULL -> "NULL"

(* Generate a uuidgen-compatible UUID (used in tests).  However to
 * avoid having the UUID change every time we rebuild the tests,
 * generate it as a function of the contents of the [actions*.ml]
 * files.
 *
 * Originally I thought uuidgen was using RFC 4122, but it doesn't
 * appear to.
 *
 * Note that the format must be 01234567-0123-0123-0123-0123456789ab
 *)
let stable_uuid =
  let cmd = "cat generator/actions*.ml" in
  let chan = open_process_in cmd in
  let s = Digest.channel chan (-1) in
  (match close_process_in chan with
  | WEXITED 0 -> ()
  | WEXITED i ->
    failwithf "command exited with non-zero status (%d)" i
  | WSIGNALED i | WSTOPPED i ->
    failwithf "command signalled or stopped with non-zero status (%d)" i
  );

  let s = Digest.to_hex s in

  (* In util-linux <= 2.19, mkswap -U cannot handle the first byte of
   * the UUID being zero, so we artificially rewrite such UUIDs.
   * http://article.gmane.org/gmane.linux.utilities.util-linux-ng/4273
   *)
  let s =
    if s.[0] = '0' && s.[1] = '0' then
      "1" ^ String.sub s 1 (String.length s - 1)
    else s in

  String.sub s 0 8 ^ "-"
  ^ String.sub s 8 4 ^ "-"
  ^ String.sub s 12 4 ^ "-"
  ^ String.sub s 16 4 ^ "-"
  ^ String.sub s 20 12

type rstructs_used_t = RStructOnly | RStructListOnly | RStructAndList

(* Returns a list of RStruct/RStructList structs that are returned
 * by any function.  Each element of returned list is a pair:
 *
 * (structname, RStructOnly)
 *    == there exists function which returns RStruct (_, structname)
 * (structname, RStructListOnly)
 *    == there exists function which returns RStructList (_, structname)
 * (structname, RStructAndList)
 *    == there are functions returning both RStruct (_, structname)
 *                                      and RStructList (_, structname)
 *)
let rstructs_used_by functions =
  (* ||| is a "logical OR" for rstructs_used_t *)
  let (|||) a b =
    match a, b with
    | RStructAndList, _
    | _, RStructAndList -> RStructAndList
    | RStructOnly, RStructListOnly
    | RStructListOnly, RStructOnly -> RStructAndList
    | RStructOnly, RStructOnly -> RStructOnly
    | RStructListOnly, RStructListOnly -> RStructListOnly
  in

  let h = Hashtbl.create 13 in

  (* if elem->oldv exists, update entry using ||| operator,
   * else just add elem->newv to the hash
   *)
  let update elem newv =
    try  let oldv = Hashtbl.find h elem in
         Hashtbl.replace h elem (newv ||| oldv)
    with Not_found -> Hashtbl.add h elem newv
  in

  List.iter (
    fun { style = ret, _, _ } ->
      match ret with
      | RStruct (_, structname) -> update structname RStructOnly
      | RStructList (_, structname) -> update structname RStructListOnly
      | _ -> ()
  ) functions;

  (* return key->values as a list of (key,value) *)
  Hashtbl.fold (fun key value xs -> (key, value) :: xs) h []

let files_equal n1 n2 =
  let cmd = sprintf "cmp -s %s %s" (Filename.quote n1) (Filename.quote n2) in
  match Sys.command cmd with
  | 0 -> true
  | 1 -> false
  | i -> failwithf "%s: failed with error code %d" cmd i

let name_of_argt = function
  | String (_, n) | StringList (_, n)
  | OptString n
  | Bool n | Int n | Int64 n
  | BufferIn n | Pointer (_, n) -> n

let name_of_optargt = function
  | OBool n | OInt n | OInt64 n | OString n | OStringList n -> n

let seq_of_test = function
  | TestRun s
  | TestResult (s, _)
  | TestResultString (s, _)
  | TestResultDevice (s, _)
  | TestResultTrue s
  | TestResultFalse s
  | TestLastFail s
  | TestRunOrUnsupported s -> s

let c_quote str =
  let str = String.replace str "\\" "\\\\" in
  let str = String.replace str "\r" "\\r" in
  let str = String.replace str "\n" "\\n" in
  let str = String.replace str "\t" "\\t" in
  let str = String.replace str "\000" "\\0" in
  let str = String.replace str "\"" "\\\"" in
  str

let html_escape text =
  let text = String.replace text "&" "&amp;" in
  let text = String.replace text "<" "&lt;" in
  let text = String.replace text ">" "&gt;" in
  text

(* Used to memoize the result of pod2text. *)
type memo_key = int option * bool * bool * string * string
                (* width,    trim, discard, name,   longdesc *)
type memo_value = string list (* list of lines of POD file *)

let pod2text_memo_filename = "generator/.pod2text.data.version.2"
let pod2text_memo : (memo_key, memo_value) Hashtbl.t =
  try with_open_in pod2text_memo_filename input_value
  with  _ -> Hashtbl.create 13
let pod2text_memo_unsaved_count = ref 0
let pod2text_memo_atexit = ref false
let pod2text_memo_save () =
  with_open_out pod2text_memo_filename
                (fun chan -> output_value chan pod2text_memo)
let pod2text_memo_updated () =
  if not (!pod2text_memo_atexit) then (
    at_exit pod2text_memo_save;
    pod2text_memo_atexit := true;
  );
  pod2text_memo_unsaved_count := !pod2text_memo_unsaved_count + 1;
  if !pod2text_memo_unsaved_count >= 100 then (
    pod2text_memo_save ();
    pod2text_memo_unsaved_count := 0;
  )

(* Useful if you need the longdesc POD text as plain text.  Returns a
 * list of lines.
 *
 * Because this is very slow (the slowest part of autogeneration),
 * we memoize the results.
 *)
let pod2text ?width ?(trim = true) ?(discard = true) name longdesc =
  let key : memo_key = width, trim, discard, name, longdesc in
  try Hashtbl.find pod2text_memo key
  with Not_found ->
    let filename, chan = Filename.open_temp_file "gen" ".tmp" in
    fprintf chan "=encoding utf8\n\n";
    fprintf chan "=head1 %s\n\n%s\n" name longdesc;
    close_out chan;
    let cmd =
      match width with
      | Some width ->
          sprintf "pod2text -w %d %s" width (Filename.quote filename)
      | None ->
          sprintf "pod2text %s" (Filename.quote filename) in
    let chan = open_process_in cmd in
    let lines = ref [] in
    let rec loop i =
      let line = input_line chan in
      if i = 1 && discard then  (* discard the first line of output *)
        loop (i+1)
      else (
        let line = if trim then String.triml line else line in
        lines := line :: !lines;
        loop (i+1)
      ) in
    let lines : memo_value = try loop 1 with End_of_file -> List.rev !lines in
    unlink filename;
    (match close_process_in chan with
     | WEXITED 0 -> ()
     | WEXITED i ->
         failwithf "pod2text: process exited with non-zero status (%d)" i
     | WSIGNALED i | WSTOPPED i ->
         failwithf "pod2text: process signalled or stopped by signal %d" i
    );
    Hashtbl.add pod2text_memo key lines;
    pod2text_memo_updated ();
    lines

(* Compare two actions (for sorting). *)
let action_compare { name = n1 } { name = n2 } = compare n1 n2

let args_of_optargs optargs =
  List.map (
    function
    | OBool n -> Bool n
    | OInt n -> Int n
    | OInt64 n -> Int64 n
    | OString n -> String (PlainString, n)
    | OStringList n -> StringList (PlainString, n)
  ) optargs
