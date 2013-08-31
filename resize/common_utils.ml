(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2010-2013 Red Hat Inc.
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

open Common_gettext.Gettext

module G = Guestfs

let (//) = Filename.concat

let ( +^ ) = Int64.add
let ( -^ ) = Int64.sub
let ( *^ ) = Int64.mul
let ( /^ ) = Int64.div
let ( &^ ) = Int64.logand
let ( ~^ ) = Int64.lognot

let int_of_le32 str =
  assert (String.length str = 4);
  let c0 = Char.code (String.unsafe_get str 0) in
  let c1 = Char.code (String.unsafe_get str 1) in
  let c2 = Char.code (String.unsafe_get str 2) in
  let c3 = Char.code (String.unsafe_get str 3) in
  Int64.of_int c0 +^
    (Int64.shift_left (Int64.of_int c1) 8) +^
    (Int64.shift_left (Int64.of_int c2) 16) +^
    (Int64.shift_left (Int64.of_int c3) 24)

let le32_of_int i =
  let c0 = i &^ 0xffL in
  let c1 = Int64.shift_right (i &^ 0xff00L) 8 in
  let c2 = Int64.shift_right (i &^ 0xff0000L) 16 in
  let c3 = Int64.shift_right (i &^ 0xff000000L) 24 in
  let s = String.create 4 in
  String.unsafe_set s 0 (Char.unsafe_chr (Int64.to_int c0));
  String.unsafe_set s 1 (Char.unsafe_chr (Int64.to_int c1));
  String.unsafe_set s 2 (Char.unsafe_chr (Int64.to_int c2));
  String.unsafe_set s 3 (Char.unsafe_chr (Int64.to_int c3));
  s

let output_spaces chan n = for i = 0 to n-1 do output_char chan ' ' done

let wrap ?(chan = stdout) ?(hanging = 0) str =
  let rec _wrap col str =
    let n = String.length str in
    let i = try String.index str ' ' with Not_found -> n in
    let col =
      if col+i >= 72 then (
        output_char chan '\n';
        output_spaces chan hanging;
        i+hanging+1
      ) else col+i+1 in
    output_string chan (String.sub str 0 i);
    if i < n then (
      output_char chan ' ';
      _wrap col (String.sub str (i+1) (n-(i+1)))
    )
  in
  _wrap 0 str

let string_prefix str prefix =
  let n = String.length prefix in
  String.length str >= n && String.sub str 0 n = prefix

let rec string_find s sub =
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
  let i = string_find s s1 in
  if i = -1 then s
  else (
    let s' = String.sub s 0 i in
    let s'' = String.sub s (i+sublen) (len-i-sublen) in
    s' ^ s2 ^ replace_str s'' s1 s2
  )

(* Split a string into multiple strings at each separator. *)
let rec string_nsplit sep str =
  let len = String.length str in
  let seplen = String.length sep in
  let i = string_find str sep in
  if i = -1 then [str]
  else (
    let s' = String.sub str 0 i in
    let s'' = String.sub str (i+seplen) (len-i-seplen) in
    s' :: string_nsplit sep s''
  )

(* Split a string at the first occurrence of the separator, returning
 * the part before and the part after.  If separator is not found,
 * return the whole string and an empty string.
 *)
let string_split sep str =
  let len = String.length sep in
  let seplen = String.length str in
  let i = string_find str sep in

  if i = -1 then str, ""
  else (
    String.sub str 0 i, String.sub str (i + len) (seplen - i - len)
  )

let string_random8 =
  let chars = "abcdefghijklmnopqrstuvwxyz0123456789" in
  fun () ->
    String.concat "" (
      List.map (
        fun _ ->
          let c = Random.int 36 in
          let c = chars.[c] in
          String.make 1 c
      ) [1;2;3;4;5;6;7;8]
    )

let error fs =
  let display str =
    wrap ~chan:stderr (s_"virt-resize: error: " ^ str);
    prerr_newline ();
    prerr_newline ();
    wrap ~chan:stderr
      (s_"If reporting bugs, run virt-resize with the '-d' option and include the complete output.");
    prerr_newline ();
    exit 1
  in
  ksprintf display fs

let read_whole_file path =
  let buf = Buffer.create 16384 in
  let chan = open_in path in
  let maxlen = 16384 in
  let s = String.create maxlen in
  let rec loop () =
    let r = input chan s 0 maxlen in
    if r > 0 then (
      Buffer.add_substring buf s 0 r;
      loop ()
    )
  in
  loop ();
  close_in chan;
  Buffer.contents buf

(* Parse the size field from --resize and --resize-force options. *)
let parse_size =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$"
  and plus_const_re = Str.regexp "^\\+\\([.0-9]+\\)\\([bKMG]\\)$"
  and minus_const_re = Str.regexp "^-\\([.0-9]+\\)\\([bKMG]\\)$"
  and percent_re = Str.regexp "^\\([.0-9]+\\)%$"
  and plus_percent_re = Str.regexp "^\\+\\([.0-9]+\\)%$"
  and minus_percent_re = Str.regexp "^-\\([.0-9]+\\)%$"
  in
  fun oldsize field ->
    let matches rex = Str.string_match rex field 0 in
    let sub i = Str.matched_group i field in
    let size_scaled f = function
      | "b" -> Int64.of_float f
      | "K" -> Int64.of_float (f *. 1024.)
      | "M" -> Int64.of_float (f *. 1024. *. 1024.)
      | "G" -> Int64.of_float (f *. 1024. *. 1024. *. 1024.)
      | _ -> assert false
    in

    if matches const_re then (
      size_scaled (float_of_string (sub 1)) (sub 2)
    )
    else if matches plus_const_re then (
      let incr = size_scaled (float_of_string (sub 1)) (sub 2) in
      oldsize +^ incr
    )
    else if matches minus_const_re then (
      let incr = size_scaled (float_of_string (sub 1)) (sub 2) in
      oldsize -^ incr
    )
    else if matches percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize *^ percent /^ 1000L
    )
    else if matches plus_percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize +^ oldsize *^ percent /^ 1000L
    )
    else if matches minus_percent_re then (
      let percent = Int64.of_float (10. *. float_of_string (sub 1)) in
      oldsize -^ oldsize *^ percent /^ 1000L
    )
    else
      error "virt-resize: %s: cannot parse size field" field

let human_size i =
  let sign, i = if i < 0L then "-", Int64.neg i else "", i in

  if i < 1024L then
    sprintf "%s%Ld" sign i
  else (
    let f = Int64.to_float i /. 1024. in
    let i = i /^ 1024L in
    if i < 1024L then
      sprintf "%s%.1fK" sign f
    else (
      let f = Int64.to_float i /. 1024. in
      let i = i /^ 1024L in
      if i < 1024L then
        sprintf "%s%.1fM" sign f
      else (
        let f = Int64.to_float i /. 1024. in
        (*let i = i /^ 1024L in*)
        sprintf "%s%.1fG" sign f
      )
    )
  )

(* Skip any leading '-' characters when comparing command line args. *)
let skip_dashes str =
  let n = String.length str in
  let rec loop i =
    if i >= n then invalid_arg "skip_dashes"
    else if String.unsafe_get str i = '-' then loop (i+1)
    else i
  in
  let i = loop 0 in
  if i = 0 then str
  else String.sub str i (n-i)

let compare_command_line_args a b =
  compare (String.lowercase (skip_dashes a)) (String.lowercase (skip_dashes b))

(* Implements `--long-options'. *)
let long_options = ref ([] : (Arg.key * Arg.spec * Arg.doc) list)
let display_long_options () =
  List.iter (
    fun (arg, _, _) ->
      if string_prefix arg "--" && arg <> "--long-options" then
        printf "%s\n" arg
  ) !long_options;
  exit 0

let uuidgen () =
  let cmd = "uuidgen -r" in
  let chan = Unix.open_process_in cmd in
  let uuid = input_line chan in
  let stat = Unix.close_process_in chan in
  (match stat with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED i ->
    error (f_"external command '%s' exited with error %d") cmd i
  | Unix.WSIGNALED i ->
    error (f_"external command '%s' killed by signal %d") cmd i
  | Unix.WSTOPPED i ->
    error (f_"external command '%s' stopped by signal %d") cmd i
  );
  let len = String.length uuid in
  let uuid, len =
    if len > 0 && uuid.[len-1] = '\n' then
      String.sub uuid 0 (len-1), len-1
    else
      uuid, len in
  if len < 10 then assert false; (* sanity check on uuidgen *)
  uuid

(* Unlink a temporary file on exit. *)
let unlink_on_exit =
  let files = ref [] in
  let registered_handlers = ref false in

  let rec unlink_files () =
    List.iter (
      fun file -> try Unix.unlink file with _ -> ()
    ) !files
  and register_handlers () =
    (* Unlink on exit. *)
    at_exit unlink_files
  in

  fun file ->
    files := file :: !files;
    if not !registered_handlers then (
      register_handlers ();
      registered_handlers := true
    )
