(* libguestfs
 * Copyright (C) 2009-2011 Red Hat Inc.
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

open Unix
open Printf

open Generator_types

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
 * generate it as a function of the contents of the
 * generator_actions.ml file.
 * 
 * Originally I thought uuidgen was using RFC 4122, but it doesn't
 * appear to.
 *
 * Note that the format must be 01234567-0123-0123-0123-0123456789ab
 *)
let uuidgen () =
  let s = Digest.to_hex (Digest.file "generator/generator_actions.ml") in

  (* In util-linux <= 2.19, mkswap -U cannot handle the first byte of
   * the UUID being zero, so we artificially rewrite such UUIDs.
   * http://article.gmane.org/gmane.linux.utilities.util-linux-ng/4273
   *)
  if s.[0] = '0' && s.[1] = '0' then
    s.[0] <- '1';

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
    fun (_, (ret, _, _), _, _, _, _, _) ->
      match ret with
      | RStruct (_, structname) -> update structname RStructOnly
      | RStructList (_, structname) -> update structname RStructListOnly
      | _ -> ()
  ) functions;

  (* return key->values as a list of (key,value) *)
  Hashtbl.fold (fun key value xs -> (key, value) :: xs) h []

let failwithf fs = ksprintf failwith fs

let unique = let i = ref 0 in fun () -> incr i; !i

let replace_char s c1 c2 =
  let s2 = String.copy s in
  let r = ref false in
  for i = 0 to String.length s2 - 1 do
    if String.unsafe_get s2 i = c1 then (
      String.unsafe_set s2 i c2;
      r := true
    )
  done;
  if not !r then s else s2

let isspace c =
  c = ' '
  (* || c = '\f' *) || c = '\n' || c = '\r' || c = '\t' (* || c = '\v' *)

let triml ?(test = isspace) str =
  let i = ref 0 in
  let n = ref (String.length str) in
  while !n > 0 && test str.[!i]; do
    decr n;
    incr i
  done;
  if !i = 0 then str
  else String.sub str !i !n

let trimr ?(test = isspace) str =
  let n = ref (String.length str) in
  while !n > 0 && test str.[!n-1]; do
    decr n
  done;
  if !n = String.length str then str
  else String.sub str 0 !n

let trim ?(test = isspace) str =
  trimr ~test (triml ~test str)

let rec find s sub =
  let len = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i <= len-sublen then (
      let rec loop2 j =
        if j < sublen then (
          if s.[i+j] = sub.[j] then loop2 (j+1)
          else -1
        ) else
          i (* found *)
      in
      let r = loop2 0 in
      if r = -1 then loop (i+1) else r
    ) else
      -1 (* not found *)
  in
  loop 0

let rec replace_str s s1 s2 =
  let len = String.length s in
  let sublen = String.length s1 in
  let i = find s s1 in
  if i = -1 then s
  else (
    let s' = String.sub s 0 i in
    let s'' = String.sub s (i+sublen) (len-i-sublen) in
    s' ^ s2 ^ replace_str s'' s1 s2
  )

let rec string_split sep str =
  let len = String.length str in
  let seplen = String.length sep in
  let i = find str sep in
  if i = -1 then [str]
  else (
    let s' = String.sub str 0 i in
    let s'' = String.sub str (i+seplen) (len-i-seplen) in
    s' :: string_split sep s''
  )

let files_equal n1 n2 =
  let cmd = sprintf "cmp -s %s %s" (Filename.quote n1) (Filename.quote n2) in
  match Sys.command cmd with
  | 0 -> true
  | 1 -> false
  | i -> failwithf "%s: failed with error code %d" cmd i

let rec filter_map f = function
  | [] -> []
  | x :: xs ->
      match f x with
      | Some y -> y :: filter_map f xs
      | None -> filter_map f xs

let rec find_map f = function
  | [] -> raise Not_found
  | x :: xs ->
      match f x with
      | Some y -> y
      | None -> find_map f xs

let iteri f xs =
  let rec loop i = function
    | [] -> ()
    | x :: xs -> f i x; loop (i+1) xs
  in
  loop 0 xs

let mapi f xs =
  let rec loop i = function
    | [] -> []
    | x :: xs -> let r = f i x in r :: loop (i+1) xs
  in
  loop 0 xs

let count_chars c str =
  let count = ref 0 in
  for i = 0 to String.length str - 1 do
    if c = String.unsafe_get str i then incr count
  done;
  !count

let explode str =
  let r = ref [] in
  for i = 0 to String.length str - 1 do
    let c = String.unsafe_get str i in
    r := c :: !r;
  done;
  List.rev !r

let map_chars f str =
  List.map f (explode str)

let name_of_argt = function
  | Pathname n | Device n | Dev_or_Path n | String n | OptString n
  | StringList n | DeviceList n | Bool n | Int n | Int64 n
  | FileIn n | FileOut n | BufferIn n | Key n | Pointer (_, n) -> n

let name_of_optargt = function
  | OBool n | OInt n | OInt64 n | OString n -> n

let seq_of_test = function
  | TestRun s | TestOutput (s, _) | TestOutputList (s, _)
  | TestOutputListOfDevices (s, _)
  | TestOutputInt (s, _) | TestOutputIntOp (s, _, _)
  | TestOutputTrue s | TestOutputFalse s
  | TestOutputLength (s, _) | TestOutputBuffer (s, _)
  | TestOutputStruct (s, _)
  | TestOutputFileMD5 (s, _)
  | TestOutputDevice (s, _)
  | TestOutputHashtable (s, _)
  | TestLastFail s -> s

let c_quote str =
  let str = replace_str str "\\" "\\\\" in
  let str = replace_str str "\r" "\\r" in
  let str = replace_str str "\n" "\\n" in
  let str = replace_str str "\t" "\\t" in
  let str = replace_str str "\000" "\\0" in
  let str = replace_str str "\"" "\\\"" in
  str

(* Used to memoize the result of pod2text. *)
let pod2text_memo_filename = "generator/.pod2text.data.version.2"
let pod2text_memo : ((int option * bool * bool * string * string), string list) Hashtbl.t =
  try
    let chan = open_in pod2text_memo_filename in
    let v = input_value chan in
    close_in chan;
    v
  with
    _ -> Hashtbl.create 13
let pod2text_memo_updated () =
  let chan = open_out pod2text_memo_filename in
  output_value chan pod2text_memo;
  close_out chan

(* Useful if you need the longdesc POD text as plain text.  Returns a
 * list of lines.
 *
 * Because this is very slow (the slowest part of autogeneration),
 * we memoize the results.
 *)
let pod2text ?width ?(trim = true) ?(discard = true) name longdesc =
  let key = width, trim, discard, name, longdesc in
  try Hashtbl.find pod2text_memo key
  with Not_found ->
    let filename, chan = Filename.open_temp_file "gen" ".tmp" in
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
        let line = if trim then triml line else line in
        lines := line :: !lines;
        loop (i+1)
      ) in
    let lines = try loop 1 with End_of_file -> List.rev !lines in
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
let action_compare (n1,_,_,_,_,_,_) (n2,_,_,_,_,_,_) = compare n1 n2

let chars c n =
  let str = String.create n in
  for i = 0 to n-1 do
    String.unsafe_set str i c
  done;
  str

let spaces n = chars ' ' n

let args_of_optargs optargs =
  List.map (
    function
    | OBool n -> Bool n
    | OInt n -> Int n
    | OInt64 n -> Int64 n
    | OString n -> String n
  ) optargs;
