(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2010-2017 Red Hat Inc.
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

(* The parts between <stdlib>..</stdlib> are copied into the
 * generator/common_utils.ml file.  These parts must ONLY use
 * functions from the OCaml stdlib.
 *)
(*<stdlib>*)
open Printf
(*</stdlib>*)

open Common_gettext.Gettext
open Getopt.OptionName

external c_inspect_decrypt : Guestfs.t -> int64 -> unit = "guestfs_int_mllib_inspect_decrypt"
external c_set_echo_keys : unit -> unit = "guestfs_int_mllib_set_echo_keys" "noalloc"
external c_set_keys_from_stdin : unit -> unit = "guestfs_int_mllib_set_keys_from_stdin" "noalloc"

(*<stdlib>*)

module Char = struct
    include Char

    let lowercase_ascii c =
      if (c >= 'A' && c <= 'Z')
      then unsafe_chr (code c + 32)
      else c

    let uppercase_ascii c =
      if (c >= 'a' && c <= 'z')
      then unsafe_chr (code c - 32)
      else c

    let isspace c =
      c = ' '
      (* || c = '\f' *) || c = '\n' || c = '\r' || c = '\t' (* || c = '\v' *)

    let isdigit = function
      | '0'..'9' -> true
      | _ -> false

    let isxdigit = function
      | '0'..'9' -> true
      | 'a'..'f' -> true
      | 'A'..'F' -> true
      | _ -> false

    let isalpha = function
      | 'a'..'z' -> true
      | 'A'..'Z' -> true
      | _ -> false

    let isalnum = function
      | '0'..'9' -> true
      | 'a'..'z' -> true
      | 'A'..'Z' -> true
      | _ -> false

    let hexdigit = function
      | '0' -> 0
      | '1' -> 1
      | '2' -> 2
      | '3' -> 3
      | '4' -> 4
      | '5' -> 5
      | '6' -> 6
      | '7' -> 7
      | '8' -> 8
      | '9' -> 9
      | 'a' | 'A' -> 10
      | 'b' | 'B' -> 11
      | 'c' | 'C' -> 12
      | 'd' | 'D' -> 13
      | 'e' | 'E' -> 14
      | 'f' | 'F' -> 15
      | _ -> -1
end

module String = struct
    include String

    let map f s =
      let len = String.length s in
      let b = Bytes.create len in
      for i = 0 to len-1 do
        Bytes.unsafe_set b i (f (unsafe_get s i))
      done;
      Bytes.to_string b

    let lowercase_ascii s = map Char.lowercase_ascii s
    let uppercase_ascii s = map Char.uppercase_ascii s

    let capitalize_ascii s =
      let b = Bytes.of_string s in
      Bytes.unsafe_set b 0 (Char.uppercase_ascii (Bytes.unsafe_get b 0));
      Bytes.to_string b

    let is_prefix str prefix =
      let n = length prefix in
      length str >= n && sub str 0 n = prefix

    let is_suffix str suffix =
      let sufflen = length suffix
      and len = length str in
      len >= sufflen && sub str (len - sufflen) sufflen = suffix

    let rec find s sub =
      let len = length s in
      let sublen = length sub in
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

    let rec replace s s1 s2 =
      let len = length s in
      let sublen = length s1 in
      let i = find s s1 in
      if i = -1 then s
      else (
        let s' = sub s 0 i in
        let s'' = sub s (i+sublen) (len-i-sublen) in
        s' ^ s2 ^ replace s'' s1 s2
      )

    let replace_char s c1 c2 =
      let b2 = Bytes.of_string s in
      let r = ref false in
      for i = 0 to Bytes.length b2 - 1 do
        if Bytes.unsafe_get b2 i = c1 then (
          Bytes.unsafe_set b2 i c2;
          r := true
        )
      done;
      if not !r then s else Bytes.to_string b2

    let rec nsplit sep str =
      let len = length str in
      let seplen = length sep in
      let i = find str sep in
      if i = -1 then [str]
      else (
        let s' = sub str 0 i in
        let s'' = sub str (i+seplen) (len-i-seplen) in
        s' :: nsplit sep s''
      )

    let split sep str =
      let len = length sep in
      let seplen = length str in
      let i = find str sep in
      if i = -1 then str, ""
      else (
        sub str 0 i, sub str (i + len) (seplen - i - len)
      )

    let rec lines_split str =
      let buf = Buffer.create 16 in
      let len = length str in
      let rec loop start len =
        try
          let i = index_from str start '\n' in
          if i > 0 && str.[i-1] = '\\' then (
            Buffer.add_substring buf str start (i-start-1);
            Buffer.add_char buf '\n';
            loop (i+1) len
          ) else (
            Buffer.add_substring buf str start (i-start);
            i+1
          )
        with Not_found ->
          if len > 0 && str.[len-1] = '\\' then (
            Buffer.add_substring buf str start (len-start-1);
            Buffer.add_char buf '\n'
          ) else
            Buffer.add_substring buf str start (len-start);
          len+1
      in
      let endi = loop 0 len in
      let line = Buffer.contents buf in
      if endi > len then
        [line]
      else
        line :: lines_split (sub str endi (len-endi))

    let random8 =
      let chars = "abcdefghijklmnopqrstuvwxyz0123456789" in
      fun () ->
      concat "" (
        List.map (
          fun _ ->
            let c = Random.int 36 in
            let c = chars.[c] in
            make 1 c
        ) [1;2;3;4;5;6;7;8]
      )

    let triml ?(test = Char.isspace) str =
      let i = ref 0 in
      let n = ref (String.length str) in
      while !n > 0 && test str.[!i]; do
        decr n;
        incr i
      done;
      if !i = 0 then str
      else String.sub str !i !n

    let trimr ?(test = Char.isspace) str =
      let n = ref (String.length str) in
      while !n > 0 && test str.[!n-1]; do
        decr n
      done;
      if !n = String.length str then str
      else String.sub str 0 !n

    let trim ?(test = Char.isspace) str =
      trimr ~test (triml ~test str)

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

    let spaces n = String.make n ' '
end

let (//) = Filename.concat
let quote = Filename.quote

let subdirectory parent path =
  if path = parent then
    ""
  else if String.is_prefix path (parent // "") then (
    let len = String.length parent in
    String.sub path (len+1) (String.length path - len-1)
  ) else
    invalid_arg (sprintf "%S is not a path prefix of %S" parent path)

let ( +^ ) = Int64.add
let ( -^ ) = Int64.sub
let ( *^ ) = Int64.mul
let ( /^ ) = Int64.div
let ( &^ ) = Int64.logand
let ( ~^ ) = Int64.lognot

external identity : 'a -> 'a = "%identity"

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
  let b = Bytes.create 4 in
  Bytes.unsafe_set b 0 (Char.unsafe_chr (Int64.to_int c0));
  Bytes.unsafe_set b 1 (Char.unsafe_chr (Int64.to_int c1));
  Bytes.unsafe_set b 2 (Char.unsafe_chr (Int64.to_int c2));
  Bytes.unsafe_set b 3 (Char.unsafe_chr (Int64.to_int c3));
  Bytes.to_string b

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
    output chan (Bytes.of_string str) i (j-i);
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

let (|>) x f = f x

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

let rec assoc ?(cmp = compare) ~default x = function
  | [] -> default
  | (y, y') :: _ when cmp x y = 0 -> y'
  | _ :: ys -> assoc ~cmp ~default x ys

let uniq ?(cmp = Pervasives.compare) xs =
  let rec loop acc = function
    | [] -> acc
    | [x] -> x :: acc
    | x :: (y :: _ as xs) when cmp x y = 0 ->
       loop acc xs
    | x :: (y :: _ as xs) ->
       loop (x :: acc) xs
  in
  List.rev (loop [] xs)

let sort_uniq ?(cmp = Pervasives.compare) xs =
  let xs = List.sort cmp xs in
  let xs = uniq ~cmp xs in
  xs

let remove_duplicates xs =
  let h = Hashtbl.create (List.length xs) in
  let rec loop = function
    | [] -> []
    | x :: xs when Hashtbl.mem h x -> xs
    | x :: xs -> Hashtbl.add h x true; x :: loop xs
  in
  loop xs

let push_back xsp x = xsp := !xsp @ [x]
let push_front x xsp = xsp := x :: !xsp
let pop_back xsp =
  let x, xs =
    match List.rev !xsp with
    | x :: xs -> x, xs
    | [] -> failwith "pop" in
  xsp := List.rev xs;
  x
let pop_front xsp =
  let x, xs =
    match !xsp with
    | x :: xs -> x, xs
    | [] -> failwith "shift" in
  xsp := xs;
  x

let append xsp xs = xsp := !xsp @ xs
let prepend xs xsp = xsp := xs @ !xsp

let unique = let i = ref 0 in fun () -> incr i; !i

let may f = function
  | None -> ()
  | Some x -> f x

type ('a, 'b) maybe = Either of 'a | Or of 'b

let protect ~f ~finally =
  let r =
    try Either (f ())
    with exn -> Or exn in
  finally ();
  match r with Either ret -> ret | Or exn -> raise exn

let failwithf fs = ksprintf failwith fs

exception Executable_not_found of string (* executable *)

let which executable =
  let paths =
    try String.nsplit ":" (Sys.getenv "PATH")
    with Not_found -> [] in
  let paths = filter_map (
    fun p ->
      let path = p // executable in
      try Unix.access path [Unix.X_OK]; Some path
      with Unix.Unix_error _ -> None
  ) paths in
  match paths with
  | [] -> raise (Executable_not_found executable)
  | x :: _ -> x

(* Program name. *)
let prog = Filename.basename Sys.executable_name

(* Stores the colours (--colours), quiet (--quiet), trace (-x) and
 * verbose (-v) flags in a global variable.
 *)
let colours = ref false
let set_colours () = colours := true
let colours () = !colours

let quiet = ref false
let set_quiet () = quiet := true
let quiet () = !quiet

let trace = ref false
let set_trace () = trace := true
let trace () = !trace

let verbose = ref false
let set_verbose () = verbose := true
let verbose () = !verbose

(* ANSI terminal colours. *)
let istty chan =
  Unix.isatty (Unix.descr_of_out_channel chan)

let ansi_green ?(chan = stdout) () =
  if colours () || istty chan then output_string chan "\x1b[0;32m"
let ansi_red ?(chan = stdout) () =
  if colours () || istty chan then output_string chan "\x1b[1;31m"
let ansi_blue ?(chan = stdout) () =
  if colours () || istty chan then output_string chan "\x1b[1;34m"
let ansi_magenta ?(chan = stdout) () =
  if colours () || istty chan then output_string chan "\x1b[1;35m"
let ansi_restore ?(chan = stdout) () =
  if colours () || istty chan then output_string chan "\x1b[0m"

(*</stdlib>*)

(* Timestamped progress messages, used for ordinary messages when not
 * --quiet.
 *)
let start_t = Unix.gettimeofday ()
let message fs =
  let display str =
    if not (quiet ()) then (
      let t = sprintf "%.1f" (Unix.gettimeofday () -. start_t) in
      printf "[%6s] " t;
      ansi_green ();
      printf "%s" str;
      ansi_restore ();
      print_newline ()
    )
  in
  ksprintf display fs

(* Error messages etc. *)
let error ?(exit_code = 1) fs =
  let display str =
    let chan = stderr in
    ansi_red ~chan ();
    wrap ~chan (sprintf (f_"%s: error: %s") prog str);
    if not (verbose () && trace ()) then (
      prerr_newline ();
      prerr_newline ();
      wrap ~chan
           (sprintf (f_"If reporting bugs, run %s with debugging enabled and include the complete output:\n\n  %s -v -x [...]")
                    prog prog);
    );
    ansi_restore ~chan ();
    prerr_newline ();
    exit exit_code
  in
  ksprintf display fs

let warning fs =
  let display str =
    let chan = stdout in
    ansi_blue ~chan ();
    wrap ~chan (sprintf (f_"%s: warning: %s") prog str);
    ansi_restore ~chan ();
    print_newline ();
  in
  ksprintf display fs

let info fs =
  let display str =
    let chan = stdout in
    ansi_magenta ~chan ();
    wrap ~chan (sprintf (f_"%s: %s") prog str);
    ansi_restore ~chan ();
    print_newline ();
  in
  ksprintf display fs

(* Print a debug message. *)
let debug fs =
  let display str = if verbose () then prerr_endline str in
  ksprintf display fs

(* Common function to create a new Guestfs handle, with common options
 * (e.g. debug, tracing) already set.
 *)
let open_guestfs ?identifier () =
  let g = new Guestfs.guestfs () in
  if trace () then g#set_trace true;
  if verbose () then g#set_verbose true;
  may g#set_identifier identifier;
  g

(* All the OCaml virt-* programs use this wrapper to catch exceptions
 * and print them nicely.
 *)
let run_main_and_handle_errors main =
  try main ()
  with
  | Unix.Unix_error (code, fname, "") -> (* from a syscall *)
    error (f_"%s: %s") fname (Unix.error_message code)
  | Unix.Unix_error (code, fname, param) -> (* from a syscall *)
    error (f_"%s: %s: %s") fname (Unix.error_message code) param
  | Sys_error msg ->                    (* from a syscall *)
    error (f_"%s") msg
  | Guestfs.Error msg ->                (* from libguestfs *)
    error (f_"libguestfs error: %s") msg
  | Failure msg ->                      (* from failwith/failwithf *)
    error (f_"failure: %s") msg
  | Invalid_argument msg ->             (* probably should never happen *)
    error (f_"internal error: invalid argument: %s") msg
  | Assert_failure (file, line, char) -> (* should never happen *)
    error (f_"internal error: assertion failed at %s, line %d, char %d")
      file line char
  | Not_found ->                        (* should never happen *)
    error (f_"internal error: Not_found exception was thrown")
  | exn ->                              (* something not matched above *)
    error (f_"exception: %s") (Printexc.to_string exn)

(* Print the version number and exit.  Used to implement --version in
 * the OCaml tools.
 *)
let print_version_and_exit () =
  printf "%s %s\n%!" prog Guestfs_config.package_version_full;
  exit 0

let generated_by =
  sprintf (f_"generated by %s %s") prog Guestfs_config.package_version_full

let virt_tools_data_dir =
  let dir = lazy (
    try Sys.getenv "VIRT_TOOLS_DATA_DIR"
    with Not_found -> Guestfs_config.datadir // "virt-tools"
  ) in
  fun () -> Lazy.force dir

(*<stdlib>*)

let read_whole_file path =
  let buf = Buffer.create 16384 in
  let chan = open_in path in
  let maxlen = 16384 in
  let b = Bytes.create maxlen in
  let rec loop () =
    let r = input chan b 0 maxlen in
    if r > 0 then (
      Buffer.add_substring buf (Bytes.to_string b) 0 r;
      loop ()
    )
  in
  loop ();
  close_in chan;
  Buffer.contents buf

(*</stdlib>*)

(* Parse a size field, eg. "10G". *)
let parse_size =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$" in
  fun field ->
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
      error "%s: cannot parse size field" field

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
      error "%s: cannot parse resize field" field

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

let create_standard_options argspec ?anon_fun ?(key_opts = false) usage_msg =
  (** Install an exit hook to check gc consistency for --debug-gc *)
  let set_debug_gc () =
    at_exit (fun () -> Gc.compact()) in
  let argspec = [
    [ S 'V'; L"version" ], Getopt.Unit print_version_and_exit, s_"Display version and exit";
    [ S 'v'; L"verbose" ], Getopt.Unit set_verbose,  s_"Enable libguestfs debugging messages";
    [ S 'x' ],             Getopt.Unit set_trace,    s_"Enable tracing of libguestfs calls";
    [ L"debug-gc" ],       Getopt.Unit set_debug_gc, Getopt.hidden_option_description;
    [ S 'q'; L"quiet" ],   Getopt.Unit set_quiet,    s_"Don’t print progress messages";
    [ L"color"; L"colors";
      L"colour"; L"colours" ], Getopt.Unit set_colours, s_"Use ANSI colour sequences even if not tty";
  ] @ argspec in
  let argspec =
    argspec @
      (if key_opts then
      [
        [ L"echo-keys" ],       Getopt.Unit c_set_echo_keys,       s_"Don’t turn off echo for passphrases";
        [ L"keys-from-stdin" ], Getopt.Unit c_set_keys_from_stdin, s_"Read passphrases from stdin";
      ]
      else []) in
  Getopt.create argspec ?anon_fun usage_msg

(*<stdlib>*)

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
            with Failure _ -> `String n in
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

(* Annoying LVM2 returns a differing UUID strings for different
 * function calls (sometimes containing or not containing '-'
 * characters), so we have to normalize each string before
 * comparison.  c.f. 'compare_pvuuids' in virt-filesystem.
 *)
let compare_lvm2_uuids uuid1 uuid2 =
  let n1 = String.length uuid1 and n2 = String.length uuid2 in
  let rec loop i1 i2 =
    if i1 = n1 && i2 = n2 then 0            (* matching *)
    else if i1 >= n1 then 1                 (* different lengths *)
    else if i2 >= n2 then -1
    else if uuid1.[i1] = '-' then loop (i1+1) i2 (* ignore '-' characters *)
    else if uuid2.[i2] = '-' then loop i1 (i2+1)
    else (
      let c = compare uuid1.[i1] uuid2.[i2] in
      if c <> 0 then c                          (* not matching *)
      else loop (i1+1) (i2+1)
    )
  in
  loop 0 0

let stringify_args args =
  let rec quote_args = function
    | [] -> ""
    | x :: xs -> " " ^ Filename.quote x ^ quote_args xs
  in
  match args with
  | [] -> ""
  | app :: xs -> app ^ quote_args xs

(*</stdlib>*)

(* Run an external command, slurp up the output as a list of lines. *)
let external_command ?(echo_cmd = true) cmd =
  if echo_cmd then
    debug "%s" cmd;
  let chan = Unix.open_process_in cmd in
  let lines = ref [] in
  (try while true do lines := input_line chan :: !lines done
   with End_of_file -> ());
  let lines = List.rev !lines in
  let stat = Unix.close_process_in chan in
  (match stat with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED i ->
    error (f_"external command ‘%s’ exited with error %d") cmd i
  | Unix.WSIGNALED i ->
    error (f_"external command ‘%s’ killed by signal %d") cmd i
  | Unix.WSTOPPED i ->
    error (f_"external command ‘%s’ stopped by signal %d") cmd i
  );
  lines

let rec run_commands ?(echo_cmd = true) cmds =
  let res = Array.make (List.length cmds) 0 in
  let pids =
    mapi (
      fun i (args, stdout_chan, stderr_chan) ->
        let run_res = do_run args ?stdout_chan ?stderr_chan in
        match run_res with
        | Either (pid, app, outfd, errfd) ->
          Some (i, pid, app, outfd, errfd)
        | Or code ->
          res.(i) <- code;
          None
    ) cmds in
  let pids = filter_map identity pids in
  let pids = ref pids in
  while !pids <> [] do
    let pid, stat = Unix.waitpid [] 0 in
    let matching_pair, new_pids =
      List.partition (
        fun (_, p, _, _, _) ->
          pid = p
      ) !pids in
    if matching_pair <> [] then (
      let matching_pair = List.hd matching_pair in
      let idx, _, app, outfd, errfd = matching_pair in
      pids := new_pids;
      res.(idx) <- do_teardown app outfd errfd stat
    );
  done;
  Array.to_list res

and run_command ?(echo_cmd = true) ?stdout_chan ?stderr_chan args =
  let run_res = do_run args ~echo_cmd ?stdout_chan ?stderr_chan in
  match run_res with
  | Either (pid, app, outfd, errfd) ->
    let _, stat = Unix.waitpid [] pid in
    do_teardown app outfd errfd stat
  | Or code ->
    code

and do_run ?(echo_cmd = true) ?stdout_chan ?stderr_chan args =
  let app = List.hd args in
  let get_fd default = function
    | None ->
      default
    | Some fd ->
      Unix.set_close_on_exec fd;
      fd
  in
  try
    let app =
      if Filename.is_relative app then which app
      else (Unix.access app [Unix.X_OK]; app) in
    let outfd = get_fd Unix.stdout stdout_chan in
    let errfd = get_fd Unix.stderr stderr_chan in
    if echo_cmd then
      debug "%s" (stringify_args args);
    let pid = Unix.create_process app (Array.of_list args) Unix.stdin
                outfd errfd in
    Either (pid, app, stdout_chan, stderr_chan)
  with
  | Executable_not_found _ ->
    Or 127
  | Unix.Unix_error (errcode, _, _) when errcode = Unix.ENOENT ->
    Or 127

and do_teardown app outfd errfd exitstat =
  may Unix.close outfd;
  may Unix.close errfd;
  match exitstat with
  | Unix.WEXITED i ->
    i
  | Unix.WSIGNALED i ->
    error (f_"external command ‘%s’ killed by signal %d") app i
  | Unix.WSTOPPED i ->
    error (f_"external command ‘%s’ stopped by signal %d") app i

let shell_command ?(echo_cmd = true) cmd =
  if echo_cmd then
    debug "%s" cmd;
  Sys.command cmd

(* Run uuidgen to return a random UUID. *)
let uuidgen () =
  let lines = external_command "uuidgen -r" in
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

(*<stdlib>*)

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

(*</stdlib>*)

(* Remove a temporary directory on exit. *)
let rmdir_on_exit =
  let dirs = ref [] in
  let registered_handlers = ref false in

  let rec rmdirs () =
    List.iter (
      fun dir ->
        let cmd = sprintf "rm -rf %s" (Filename.quote dir) in
        ignore (shell_command cmd)
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
 * The optional filter is used to filter out files which will be
 * removed: files returning true are not removed.
 *
 * XXX Could be faster with a specific API for doing this.
 *)
let rm_rf_only_files (g : Guestfs.guestfs) ?filter dir =
  if g#is_dir dir then (
    let files = Array.map (Filename.concat dir) (g#find dir) in
    let files = Array.to_list files in
    let files = List.filter g#is_file files in
    let files = match filter with
    | None -> files
    | Some f -> List.filter (fun x -> not (f x)) files in
    List.iter g#rm files
  )

let truncate_recursive (g : Guestfs.guestfs) dir =
  let files = Array.map (Filename.concat dir) (g#find dir) in
  let files = Array.to_list files in
  let files = List.filter g#is_file files in
  List.iter g#truncate files

let debug_augeas_errors g =
  if verbose () then (
    try
      let errors = g#aug_match "/augeas/files//error" in
      let errors = Array.to_list errors in
      let map =
        List.fold_left (
          fun map error ->
            let detail_paths = g#aug_match (error ^ "//*") in
            let detail_paths = Array.to_list detail_paths in
            List.fold_left (
              fun map path ->
                (* path is "/augeas/files/<filename>/error/<field>".  Put
                 * <filename>, <field> and the value of this Augeas field
                 * into a map.
                 *)
                let i = String.find path "/error/" in
                assert (i >= 0);
                let filename = String.sub path 13 (i-13) in
                let field =
                  String.sub path (i+7) (String.length path - (i+7)) in

                let detail = g#aug_get path in

                let fmap : string StringMap.t =
                  try StringMap.find filename map
                  with Not_found -> StringMap.empty in
                let fmap = StringMap.add field detail fmap in
                StringMap.add filename fmap map
            ) map detail_paths
        ) StringMap.empty errors in

      let filenames = StringMap.keys map in
      let filenames = List.sort compare filenames in

      List.iter (
        fun filename ->
          eprintf "augeas failed to parse %s:\n" filename;
          let fmap = StringMap.find filename map in
          (try
            let msg = StringMap.find "message" fmap in
            eprintf " error \"%s\"" msg
          with Not_found -> ()
          );
          (try
            let line = StringMap.find "line" fmap
            and char = StringMap.find "char" fmap in
            eprintf " at line %s char %s" line char
          with Not_found -> ()
          );
          (try
            let lens = StringMap.find "lens" fmap in
            eprintf " in lens %s" lens
          with Not_found -> ()
          );
          eprintf "\n"
      ) filenames;

      flush stderr
    with
      Guestfs.Error msg -> eprintf "%s: augeas: %s (ignored)\n" prog msg
  )

(* Detect type of a file. *)
let detect_file_type filename =
  let chan = open_in filename in
  let get start size =
    try
      seek_in chan start;
      let b = Bytes.create size in
      really_input chan b 0 size;
      Some (Bytes.to_string b)
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

(*<stdlib>*)

let is_block_device file =
  try (Unix.stat file).Unix.st_kind = Unix.S_BLK
  with Unix.Unix_error _ -> false

let is_char_device file =
  try (Unix.stat file).Unix.st_kind = Unix.S_CHR
  with Unix.Unix_error _ -> false

(*</stdlib>*)

let is_partition dev =
  try
    if not (is_block_device dev) then false
    else (
      let rdev = (Unix.stat dev).Unix.st_rdev in
      let major = Unix_utils.Dev_t.major rdev in
      let minor = Unix_utils.Dev_t.minor rdev in
      let path = sprintf "/sys/dev/block/%d:%d/partition" major minor in
      Unix.access path [Unix.F_OK];
      true
    )
  with Unix.Unix_error _ -> false

(*<stdlib>*)

(* Annoyingly Sys.is_directory throws an exception on failure
 * (RHBZ#1022431).
 *)
let is_directory path =
  try Sys.is_directory path
  with Sys_error _ -> false

let absolute_path path =
  if not (Filename.is_relative path) then path
  else Sys.getcwd () // path

let qemu_input_filename filename =
  (* If the filename is something like "file:foo" then qemu-img will
   * try to interpret that as "foo" in the file:/// protocol.  To
   * avoid that, if the path is relative prefix it with "./" since
   * qemu-img won't try to interpret such a path.
   *)
  if String.length filename > 0 && filename.[0] <> '/' then
    "./" ^ filename
  else
    filename

let rec mkdir_p path permissions =
  try Unix.mkdir path permissions
  with
  | Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
    (* A component in the path does not exist, so first try
     * creating the parent directory, and then again the requested
     * directory. *)
    mkdir_p (Filename.dirname path) permissions;
    Unix.mkdir path permissions

let normalize_arch = function
  | "i486" | "i586" | "i686" -> "i386"
  | "amd64" -> "x86_64"
  | "powerpc" -> "ppc"
  | "powerpc64" -> "ppc64"
  | "powerpc64le" -> "ppc64le"
  | arch -> arch

(* Are guest arch and host_cpu compatible, in terms of being able
 * to run commands in the libguestfs appliance?
 *)
let guest_arch_compatible guest_arch =
  let own = normalize_arch Guestfs_config.host_cpu in
  let guest_arch = normalize_arch guest_arch in
  match own, guest_arch with
  | x, y when x = y -> true
  | "x86_64", "i386" -> true
  | _ -> false

(* Is the guest OS "Unix-like"? *)
let unix_like = function
  | "hurd"
  | "linux"
  | "minix" -> true
  | typ when String.is_suffix typ "bsd" -> true
  | _ -> false

(** Return the last part of a string, after the specified separator. *)
let last_part_of str sep =
  try
    let i = String.rindex str sep in
    Some (String.sub str (i+1) (String.length str - (i+1)))
  with Not_found -> None

let read_first_line_from_file filename =
  let chan = open_in filename in
  let line = try input_line chan with End_of_file -> "" in
  close_in chan;
  line

let is_regular_file path = (* NB: follows symlinks. *)
  try (Unix.stat path).Unix.st_kind = Unix.S_REG
  with Unix.Unix_error _ -> false

(*</stdlib>*)

let inspect_mount_root g ?mount_opts_fn root =
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) =
    compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (
    fun (mp, dev) ->
      let mountfn =
        match mount_opts_fn with
        | Some fn -> g#mount_options (fn mp)
        | None -> g#mount in
      try mountfn dev mp
      with Guestfs.Error msg -> warning (f_"%s (ignored)") msg
  ) mps

let inspect_mount_root_ro =
  inspect_mount_root ~mount_opts_fn:(fun _ -> "ro")

let is_btrfs_subvolume g fs =
  try
    ignore (g#mountable_subvolume fs); true
  with Guestfs.Error msg as exn ->
    if g#last_errno () = Guestfs.Errno.errno_EINVAL then false
    else raise exn

let inspect_decrypt g =
  (* Note we pass original 'g' even though it is not used by the
   * callee.  This is so that 'g' is kept as a root on the stack, and
   * so cannot be garbage collected while we are in the c_inspect_decrypt
   * function.
   *)
  c_inspect_decrypt g#ocaml_handle (Guestfs.c_pointer g#ocaml_handle)
