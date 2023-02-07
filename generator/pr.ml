(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Unix
open Printf

open Std_utils
open Utils

(* Output channel, 'pr' prints to this. *)
let chan = ref Pervasives.stdout

(* Number of lines generated. *)
let lines = ref 0

(* Name of each file generated. *)
let files = ref []
let fileshash = Hashtbl.create 13

(* Print-to-current-output function, used everywhere.  It has
 * printf-like semantics.
 *)
let pr fs =
  ksprintf
    (fun str ->
       let i = String.count_chars '\n' str in
       lines := !lines + i;
       output_string !chan str
    ) fs

let output_to ?(perm = 0o444) filename k =
  files := filename :: !files;
  Hashtbl.add fileshash filename ();

  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  k ();
  close_out !chan;
  chan := Pervasives.stdout;

  (* Is the new file different from the current file? *)
  if Sys.file_exists filename && files_equal filename filename_new then
    unlink filename_new                 (* same, so skip it *)
  else (
    (* different, overwrite old one *)
    (try chmod filename 0o644 with Unix_error _ -> ());
    rename filename_new filename;
    chmod filename perm;
    printf "written %s\n%!" filename;
  )

let delete_except_generated ?(skip = []) glob =
  let cmd = sprintf "ls -1 %s" glob in
  let chan = open_process_in cmd in
  let lines = ref [] in
  let rec loop () =
    lines := input_line chan :: !lines;
    loop ()
  in
  let lines = try loop () with End_of_file -> List.rev !lines in
  (match close_process_in chan with
  | WEXITED 0 -> ()
  | WEXITED i ->
    failwithf "command exited with non-zero status (%d)" i
  | WSIGNALED i | WSTOPPED i ->
    failwithf "command signalled or stopped with non-zero status (%d)" i
  );

  (* Build the final skip hash. *)
  let skiphash = Hashtbl.copy fileshash in
  List.iter (fun filename -> Hashtbl.add skiphash filename ()) skip;

  (* Remove the files. *)
  List.iter (
    fun filename ->
      if not (Hashtbl.mem skiphash filename) then (
        unlink filename;
        printf "deleted %s\n%!" filename
      )
  ) lines

let get_lines_generated () =
  !lines

let get_files_generated () =
  List.rev !files
