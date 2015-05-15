(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2010-2014 Red Hat Inc.
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

(* Return 'i' rounded up to the next multiple of 'a'. *)
let roundup64 i a = let a = a -^ 1L in (i +^ a) &^ (~^ a)
let div_roundup64 i a = (i +^ a -^ 1L) /^ a

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

type wrap_break_t = WrapEOS | WrapSpace | WrapNL

let rec wrap ?(chan = stdout) ?(indent = 0) str =
  let len = String.length str in
  _wrap chan indent 0 0 len str

and _wrap chan indent column i len str =
  if i < len then (
    let (j, break) = _wrap_find_next_break i len str in
    let next_column =
      if column + (j-i) >= 76 then (
        output_char chan '\n';
        output_spaces chan indent;
        indent + (j-i) + 1
      )
      else column + (j-i) + 1 in
    output chan str i (j-i);
    match break with
    | WrapEOS -> ()
    | WrapSpace ->
      output_char chan ' ';
      _wrap chan indent next_column (j+1) len str
    | WrapNL ->
      output_char chan '\n';
      output_spaces chan indent;
      _wrap chan indent indent (j+1) len str
  )

and _wrap_find_next_break i len str =
  if i >= len then (len, WrapEOS)
  else if String.unsafe_get str i = ' ' then (i, WrapSpace)
  else if String.unsafe_get str i = '\n' then (i, WrapNL)
  else _wrap_find_next_break (i+1) len str

and output_spaces chan n = for i = 0 to n-1 do output_char chan ' ' done

let string_prefix str prefix =
  let n = String.length prefix in
  String.length str >= n && String.sub str 0 n = prefix

let string_suffix str suffix =
  let sufflen = String.length suffix
  and len = String.length str in
  len >= sufflen && String.sub str (len - sufflen) sufflen = suffix

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

(* Drop elements from a list while a predicate is true. *)
let rec dropwhile f = function
  | [] -> []
  | x :: xs when f x -> dropwhile f xs
  | xs -> xs

(* Take elements from a list while a predicate is true. *)
let rec takewhile f = function
  | x :: xs when f x -> x :: takewhile f xs
  | _ -> []

let rec filter_map f = function
  | [] -> []
  | x :: xs ->
      match f x with
      | Some y -> y :: filter_map f xs
      | None -> filter_map f xs

let iteri f xs =
  let rec loop i = function
    | [] -> ()
    | x :: xs -> f i x; loop (i+1) xs
  in
  loop 0 xs

let rec mapi i f =
  function
  | [] -> []
  | a::l ->
    let r = f i a in
    r :: mapi (i + 1) f l
let mapi f l = mapi 0 f l

let rec combine3 xs ys zs =
  match xs, ys, zs with
  | [], [], [] -> []
  | x::xs, y::ys, z::zs -> (x, y, z) :: combine3 xs ys zs
  | _ -> invalid_arg "combine3"

(* ANSI terminal colours. *)
let ansi_green ?(chan = stdout) () =
  if TTY.isatty_stdout () then output_string chan "\x1b[0;32m"
let ansi_red ?(chan = stdout) () =
  if TTY.isatty_stdout () then output_string chan "\x1b[1;31m"
let ansi_blue ?(chan = stdout) () =
  if TTY.isatty_stdout () then output_string chan "\x1b[1;34m"
let ansi_magenta ?(chan = stdout) () =
  if TTY.isatty_stdout () then output_string chan "\x1b[1;35m"
let ansi_restore ?(chan = stdout) () =
  if TTY.isatty_stdout () then output_string chan "\x1b[0m"

(* Timestamped progress messages, used for ordinary messages when not
 * --quiet.
 *)
let start_t = Unix.time ()
let make_message_function ~quiet fs =
  let p str =
    if not quiet then (
      let t = sprintf "%.1f" (Unix.time () -. start_t) in
      printf "[%6s] " t;
      ansi_green ();
      printf "%s" str;
      ansi_restore ();
      print_newline ()
    )
  in
  ksprintf p fs

let error ~prog ?(exit_code = 1) fs =
  let display str =
    let chan = stderr in
    ansi_red ~chan ();
    wrap ~chan (sprintf (f_"%s: error: %s") prog str);
    prerr_newline ();
    prerr_newline ();
    wrap ~chan
      (sprintf (f_"If reporting bugs, run %s with debugging enabled and include the complete output:\n\n  %s -v -x [...]")
         prog prog);
    ansi_restore ~chan ();
    prerr_newline ();
    exit exit_code
  in
  ksprintf display fs

let warning ~prog fs =
  let display str =
    let chan = stderr in
    ansi_blue ~chan ();
    wrap ~chan (sprintf (f_"%s: warning: %s") prog str);
    ansi_restore ~chan ();
    prerr_newline ();
  in
  ksprintf display fs

let info ~prog fs =
  let display str =
    let chan = stdout in
    ansi_magenta ~chan ();
    wrap ~chan (sprintf (f_"%s: %s") prog str);
    ansi_restore ~chan ();
    print_newline ();
  in
  ksprintf display fs

(* All the OCaml virt-* programs use this wrapper to catch exceptions
 * and print them nicely.
 *)
let run_main_and_handle_errors ~prog main =
  try main ()
  with
  | Unix.Unix_error (code, fname, "") -> (* from a syscall *)
    error ~prog (f_"%s: %s") fname (Unix.error_message code)
  | Unix.Unix_error (code, fname, param) -> (* from a syscall *)
    error ~prog (f_"%s: %s: %s") fname (Unix.error_message code) param
  | Sys_error msg ->                    (* from a syscall *)
    error ~prog (f_"%s") msg
  | G.Error msg ->                      (* from libguestfs *)
    error ~prog (f_"libguestfs error: %s") msg
  | Failure msg ->                      (* from failwith/failwithf *)
    error ~prog (f_"failure: %s") msg
  | Invalid_argument msg ->             (* probably should never happen *)
    error ~prog (f_"internal error: invalid argument: %s") msg
  | Assert_failure (file, line, char) -> (* should never happen *)
    error ~prog (f_"internal error: assertion failed at %s, line %d, char %d")
      file line char
  | Not_found ->                        (* should never happen *)
    error ~prog (f_"internal error: Not_found exception was thrown")
  | exn ->                              (* something not matched above *)
    error ~prog (f_"exception: %s") (Printexc.to_string exn)

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

(* Parse a size field, eg. "10G". *)
let parse_size =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$" in
  fun ~prog field ->
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
    else
      error ~prog "%s: cannot parse size field" field

(* Parse a size field, eg. "10G", "+20%" etc.  Used particularly by
 * virt-resize --resize and --resize-force options.
 *)
let parse_resize =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$"
  and plus_const_re = Str.regexp "^\\+\\([.0-9]+\\)\\([bKMG]\\)$"
  and minus_const_re = Str.regexp "^-\\([.0-9]+\\)\\([bKMG]\\)$"
  and percent_re = Str.regexp "^\\([.0-9]+\\)%$"
  and plus_percent_re = Str.regexp "^\\+\\([.0-9]+\\)%$"
  and minus_percent_re = Str.regexp "^-\\([.0-9]+\\)%$"
  in
  fun ~prog oldsize field ->
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
      error ~prog "%s: cannot parse resize field" field

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

(* Compare two version strings intelligently. *)
let rex_numbers = Str.regexp "^\\([0-9]+\\)\\(.*\\)$"
let rex_letters = Str.regexp_case_fold "^\\([a-z]+\\)\\(.*\\)$"

let compare_version v1 v2 =
  let rec split_version = function
    | "" -> []
    | str ->
      let first, rest =
        if Str.string_match rex_numbers str 0 then (
          let n = Str.matched_group 1 str in
          let rest = Str.matched_group 2 str in
          let n =
            try `Number (int_of_string n)
            with Failure "int_of_string" -> `String n in
          n, rest
        )
        else if Str.string_match rex_letters str 0 then
          `String (Str.matched_group 1 str), Str.matched_group 2 str
        else (
          let len = String.length str in
          `Char str.[0], String.sub str 1 (len-1)
        ) in
      first :: split_version rest
  in
  compare (split_version v1) (split_version v2)

(* Run an external command, slurp up the output as a list of lines. *)
let external_command ~prog cmd =
  let chan = Unix.open_process_in cmd in
  let lines = ref [] in
  (try while true do lines := input_line chan :: !lines done
   with End_of_file -> ());
  let lines = List.rev !lines in
  let stat = Unix.close_process_in chan in
  (match stat with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED i ->
    error ~prog (f_"external command '%s' exited with error %d") cmd i
  | Unix.WSIGNALED i ->
    error ~prog (f_"external command '%s' killed by signal %d") cmd i
  | Unix.WSTOPPED i ->
    error ~prog (f_"external command '%s' stopped by signal %d") cmd i
  );
  lines

(* Run uuidgen to return a random UUID. *)
let uuidgen ~prog () =
  let lines = external_command ~prog "uuidgen -r" in
  assert (List.length lines >= 1);
  let uuid = List.hd lines in
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

(* Remove a temporary directory on exit. *)
let rmdir_on_exit =
  let dirs = ref [] in
  let registered_handlers = ref false in

  let rec rmdirs () =
    List.iter (
      fun dir ->
        let cmd = sprintf "rm -rf %s" (Filename.quote dir) in
        ignore (Sys.command cmd)
    ) !dirs
  and register_handlers () =
    (* Remove on exit. *)
    at_exit rmdirs
  in

  fun dir ->
    dirs := dir :: !dirs;
    if not !registered_handlers then (
      register_handlers ();
      registered_handlers := true
    )

(* Using the libguestfs API, recursively remove only files from the
 * given directory.  Useful for cleaning /var/cache etc in sysprep
 * without removing the actual directory structure.  Also if 'dir' is
 * not a directory or doesn't exist, ignore it.
 *
 * XXX Could be faster with a specific API for doing this.
 *)
let rm_rf_only_files (g : Guestfs.guestfs) dir =
  if g#is_dir dir then (
    let files = Array.map (Filename.concat dir) (g#find dir) in
    let files = Array.to_list files in
    let files = List.filter g#is_file files in
    List.iter g#rm files
  )

(* Detect type of a file. *)
let detect_file_type filename =
  let chan = open_in filename in
  let get start size =
    try
      seek_in chan start;
      let buf = String.create size in
      really_input chan buf 0 size;
      Some buf
    with End_of_file | Invalid_argument _ -> None
  in
  let ret =
    if get 0 6 = Some "\2537zXZ\000" then `XZ
    else if get 0 4 = Some "PK\003\004" then `Zip
    else if get 0 4 = Some "PK\005\006" then `Zip
    else if get 0 4 = Some "PK\007\008" then `Zip
    else if get 257 6 = Some "ustar\000" then `Tar
    else if get 257 8 = Some "ustar\x20\x20\000" then `Tar
    else if get 0 2 = Some "\x1f\x8b" then `GZip
    else `Unknown in
  close_in chan;
  ret

let is_block_device file =
  try (Unix.stat file).Unix.st_kind = Unix.S_BLK
  with Unix.Unix_error _ -> false

let is_char_device file =
  try (Unix.stat file).Unix.st_kind = Unix.S_CHR
  with Unix.Unix_error _ -> false

(* Annoyingly Sys.is_directory throws an exception on failure
 * (RHBZ#1022431).
 *)
let is_directory path =
  try Sys.is_directory path
  with Sys_error _ -> false

let absolute_path path =
  if not (Filename.is_relative path) then path
  else Sys.getcwd () // path

(* Are guest arch and host_cpu compatible, in terms of being able
 * to run commands in the libguestfs appliance?
 *)
let guest_arch_compatible guest_arch =
  match Config.host_cpu, guest_arch with
  | x, y when x = y -> true
  | "x86_64", ("i386"|"i486"|"i586"|"i686") -> true
  | _ -> false
