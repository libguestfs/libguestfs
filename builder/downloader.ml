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
open Common_utils

open Unix
open Printf

let quote = Filename.quote
let (//) = Filename.concat

let cache_of_name cachedir name arch revision =
  cachedir // sprintf "%s.%s.%d" name arch revision

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

let rec download ~prog t ?template ?progress_bar uri =
  match template with
  | None ->                       (* no cache, simple download *)
    (* Create a temporary name. *)
    let tmpfile = Filename.temp_file "vbcache" ".txt" in
    download_to ~prog t ?progress_bar uri tmpfile;
    (tmpfile, true)

  | Some (name, arch, revision) ->
    match t.cache with
    | None ->
      (* Not using the cache at all? *)
      download t ~prog ?progress_bar uri

    | Some cachedir ->
      let filename = cache_of_name cachedir name arch revision in

      (* Is the requested template name + revision in the cache already?
       * If not, download it.
       *)
      if not (Sys.file_exists filename) then
        download_to ~prog t ?progress_bar uri filename;

      (filename, false)

and download_to ~prog t ?(progress_bar = false) uri filename =
  let parseduri =
    try URI.parse_uri uri
    with Invalid_argument "URI.parse_uri" ->
      eprintf (f_"Error parsing URI '%s'. Look for error messages printed above.\n") uri;
      exit 1 in

  (* Note because there may be parallel virt-builder instances running
   * and also to avoid partial downloads in the cachedir if the network
   * fails, we download to a random name in the cache and then
   * atomically rename it to the final filename.
   *)
  let filename_new = filename ^ "." ^ string_random8 () in
  unlink_on_exit filename_new;

  (match parseduri.URI.protocol with
  | "file" ->
    let path = parseduri.URI.path in
    let cmd = sprintf "cp%s %s %s"
      (if t.debug then " -v" else "")
      (quote path) (quote filename_new) in
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"%s: cp (download) command failed copying '%s'\n")
        prog path;
      exit 1
    )
  | _ -> (* Any other protocol. *)
    (* Get the status code first to ensure the file exists. *)
    let cmd = sprintf "%s%s -g -o /dev/null -I -w '%%{http_code}' %s"
      t.curl
      (if t.debug then "" else " -s -S")
      (quote uri) in
    if t.debug then eprintf "%s\n%!" cmd;
    let lines = external_command ~prog cmd in
    if List.length lines < 1 then (
      eprintf (f_"%s: unexpected output from curl command, enable debug and look at previous messages\n")
        prog;
      exit 1
    );
    let status_code = List.hd lines in
    let bad_status_code = function
      | "" -> true
      | s when s.[0] = '4' -> true (* 4xx *)
      | s when s.[0] = '5' -> true (* 5xx *)
      | _ -> false
    in
    if bad_status_code status_code then (
      eprintf (f_"%s: failed to download %s: HTTP status code %s\n")
        prog uri status_code;
      exit 1
    );

    (* Now download the file. *)
    let cmd = sprintf "%s%s -g -o %s %s"
      t.curl
      (if t.debug then "" else if progress_bar then " -#" else " -s -S")
      (quote filename_new) (quote uri) in
    if t.debug then eprintf "%s\n%!" cmd;
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"%s: curl (download) command failed downloading '%s'\n")
        prog uri;
      exit 1
    )
  );

  (* Rename the file if the download was successful. *)
  rename filename_new filename
