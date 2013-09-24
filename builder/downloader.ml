(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

open Common_gettext.Gettext

open Unix
open Printf

let quote = Filename.quote
let (//) = Filename.concat

type uri = string
type filename = string

type t = {
  debug : bool;
  curl : string;
  cache : string option;                (* cache directory for templates *)
}

let create ~debug ~curl ~cache = {
  debug = debug;
  curl = curl;
  cache = cache;
}

let rec download t ?template uri =
  match template with
  | None ->                       (* no cache, simple download *)
    (* Create a temporary name. *)
    let tmpfile = Filename.temp_file "vbcache" ".txt" in
    download_to t uri tmpfile;
    (tmpfile, true)

  | Some (name, revision) ->
    match t.cache with
    | None ->
      (* Not using the cache at all? *)
      download t uri

    | Some cachedir ->
      let filename = cachedir // sprintf "%s.%d" name revision in

      (* Is the requested template name + revision in the cache already?
       * If not, download it.
       *)
      if not (Sys.file_exists filename) then
        download_to t uri filename;

      (filename, false)

and download_to t uri filename =
  (* Get the status code first to ensure the file exists. *)
  let cmd = sprintf "%s%s -g -o /dev/null -I -w '%%{http_code}' %s"
    t.curl (if t.debug then "" else " -s -S") (quote uri) in
  let chan = open_process_in cmd in
  let status_code = input_line chan in
  let stat = close_process_in chan in
  (match stat with
  | WEXITED 0 -> ()
  | WEXITED i ->
    eprintf (f_"virt-builder: curl (download) command failed downloading '%s'\n") uri;
    exit 1
  | WSIGNALED i ->
    eprintf (f_"virt-builder: external command '%s' killed by signal %d\n")
      cmd i;
    exit 1
  | WSTOPPED i ->
    eprintf (f_"virt-builder: external command '%s' stopped by signal %d\n")
      cmd i;
    exit 1
  );
  let bad_status_code = function
    | "" -> true
    | s when s.[0] = '4' -> true (* 4xx *)
    | s when s.[0] = '5' -> true (* 5xx *)
    | _ -> false
  in
  if bad_status_code status_code then (
    eprintf (f_"virt-builder: failed to download %s: HTTP status code %s\n")
      uri status_code;
    exit 1
  );

  (* Now download the file. *)
  let filename_new = filename ^ ".new" in
  let cmd = sprintf "%s%s -g -o %s %s"
    t.curl (if t.debug then "" else " -s -S")
    (quote filename_new) (quote uri) in
  if t.debug then eprintf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then (
    eprintf (f_"virt-builder: curl (download) command failed downloading '%s'\n") uri;
    (try unlink filename_new with _ -> ());
    exit 1
  );

  (* Rename the file if curl was successful. *)
  rename filename_new filename
