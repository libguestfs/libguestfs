#!/usr/bin/ocamlrun ocaml

(* Copyright (C) 2010-2014 Red Hat Inc.
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
#load "str.cma"

type test_result =
  | Pass
  | Skip
  | XFail
  | Fail
  | XPass
  | Error

let (//) = Filename.concat

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

let string_charsplit sep =
  Str.split (Str.regexp_string sep)

let find_trs basedir =
  let rec internal_find_trs basedir stack =
    let items = Array.to_list (Sys.readdir basedir) in
    let items = List.map (fun x -> x, basedir // x) items in
    let dirs, files = List.partition (
      fun (_, full_x) ->
        try Sys.is_directory full_x
        with Sys_error _ -> false
    ) items in
    let files = List.filter (fun (x, _) -> Filename.check_suffix x ".trs") files in
    let files = List.map (fun (_, full_x) -> stack, full_x) files in
    let subdirs_files = List.fold_left (
      fun acc (fn, dir) ->
        (internal_find_trs dir (fn :: stack)) :: acc
    ) [] dirs in
    let subdirs_files = List.rev subdirs_files in
    List.concat (files :: subdirs_files)
  in
  internal_find_trs basedir ["tests"]

let iterate_results trs_files =
  let total = ref 0 in
  let failures = ref 0 in
  let errors = ref 0 in
  let skipped = ref 0 in
  let total_time = ref 0 in
  let buf = Buffer.create 16384 in
  let read_trs file =
    let log_filename = (Filename.chop_suffix file ".trs") ^ ".log" in
    let content = read_whole_file file in
    let lines = string_charsplit "\n" content in
    let testname = ref (Filename.chop_suffix (Filename.basename file) ".trs") in
    let res = ref Pass in
    let time = ref 0 in
    List.iter (
      fun line ->
        let line = string_charsplit " " line in
        (match line with
        | ":test-result:" :: result :: rest ->
          let name = String.concat " " rest in
          if String.length name > 0 then testname := name;
          res :=
            (match result with
            | "PASS" -> Pass
            | "SKIP" -> Skip
            | "XFAIL" -> XFail
            | "FAIL" -> Fail
            | "XPASS" -> XPass
            | "ERROR" | _ -> Error);
        | ":guestfs-time:" :: delta :: _ ->
          time := int_of_string delta
        | _ -> ()
        );
    ) lines;
    !testname, !res, !time, log_filename in
  List.iter (
    fun (stack, file) ->
      let testname, result, time, log_filename = read_trs file in
      let log =
        match testname with
        | "test-virt-rescue.pl" -> ""  (* Non-printable chars in output. *)
        | _ -> try read_whole_file log_filename with _ -> "" in
      let print_tag_with_log tag =
        Buffer.add_string buf (sprintf "  <testcase name=\"%s\" classname=\"%s\" time=\"%d\">\n" testname (String.concat "." (List.rev stack)) time);
        Buffer.add_string buf (sprintf "    <%s><![CDATA[%s]]></%s>\n" tag log tag);
        Buffer.add_string buf (sprintf "  </testcase>\n")
      in
      (match result with
      | Pass ->
        print_tag_with_log "system-out"
      | Skip ->
        skipped := !skipped + 1;
        print_tag_with_log "skipped"
      | XFail | Fail | XPass ->
        failures := !failures + 1;
        print_tag_with_log "error"
      | Error ->
        errors := !errors + 1;
        print_tag_with_log "error"
      );
      total := !total + 1;
      total_time := !total_time + time
  ) trs_files;
  Buffer.contents buf, !total, !failures, !errors, !skipped, !total_time

let sort_trs (_, f1) (_, f2) =
  compare f1 f2

let () =
  if Array.length Sys.argv < 3 then (
    printf "%s PROJECTNAME BASEDIR\n" Sys.argv.(0);
    exit 1
  );
  let name = Sys.argv.(1) in
  let basedir = Sys.argv.(2) in
  let trs_files = List.sort sort_trs (find_trs basedir) in
  let buf, total, failures, errors, skipped, time =
    iterate_results trs_files in
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<testsuite name=\"%s\" tests=\"%d\" failures=\"%d\" skipped=\"%d\" errors=\"%d\" time=\"%d\">
%s</testsuite>
" name total failures skipped errors time buf
