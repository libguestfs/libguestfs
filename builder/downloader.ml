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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Utils

open Unix
open Printf

type uri = string
type filename = string

type t = {
  curl : string;
  tmpdir : string;
  cache : Cache.t option;               (* cache for templates *)
}

let create ~curl ~tmpdir ~cache = {
  curl = curl;
  tmpdir = tmpdir;
  cache = cache;
}

let rec download t ?template ?progress_bar ?(proxy = Curl.SystemProxy) uri =
  match template with
  | None ->                       (* no cache, simple download *)
    (* Create a temporary name. *)
    let tmpfile = Filename.temp_file ~temp_dir:t.tmpdir "vbcache" ".txt" in
    download_to t ?progress_bar ~proxy uri tmpfile;
    (tmpfile, true)

  | Some (name, arch, revision) ->
    match t.cache with
    | None ->
      (* Not using the cache at all? *)
      download t ?progress_bar ~proxy uri

    | Some cache ->
      let filename = Cache.cache_of_name cache name arch revision in

      (* Is the requested template name + revision in the cache already?
       * If not, download it.
       *)
      if not (Sys.file_exists filename) then
        download_to t ?progress_bar ~proxy uri filename;

      (filename, false)

and download_to t ?(progress_bar = false) ~proxy uri filename =
  let parseduri =
    try URI.parse_uri uri
    with URI.Parse_failed ->
      error (f_"error parsing URI '%s'. Look for error messages printed above.")
        uri in

  (* Note because there may be parallel virt-builder instances running
   * and also to avoid partial downloads in the cache if the network
   * fails, we download to a random name in the cache and then
   * atomically rename it to the final filename.
   *)
  let filename_new = filename ^ "." ^ String.random8 () in
  unlink_on_exit filename_new;

  (match parseduri.URI.protocol with
  (* Download (ie. copy) from a local file. *)
  | "file" ->
    let path = parseduri.URI.path in
    let cmd = [ "cp" ] @
      (if verbose () then [ "-v" ] else []) @
      [ path; filename_new ] in
    let r = run_command cmd in
    if r <> 0 then
      error (f_"cp (download) command failed copying ‘%s’") path;

  (* Any other protocol. *)
  | _ ->
    let common_args = [
      "location", None;         (* Follow 3xx redirects. *)
      "url", Some uri;          (* URI to download. *)
    ] in

    let quiet_args = [ "silent", None; "show-error", None ] in

    (* Get the status code first to ensure the file exists. *)
    let curl_h =
      let curl_args = ref common_args in
      if not (verbose ()) then append curl_args quiet_args;
      append curl_args [
        "output", Some "/dev/null"; (* Write output to /dev/null. *)
        "head", None;               (* Request only HEAD. *)
        "write-out", Some "%{http_code}" (* HTTP status code to stdout. *)
      ];

      Curl.create ~curl:t.curl ~tmpdir:t.tmpdir !curl_args in

    let lines = Curl.run curl_h in
    if List.length lines < 1 then
      error (f_"unexpected output from curl command, enable debug and look at previous messages");
    let status_code = List.hd lines in
    let bad_status_code = function
      | "" -> true
      | s when s.[0] = '4' -> true (* 4xx *)
      | s when s.[0] = '5' -> true (* 5xx *)
      | _ -> false
    in
    if bad_status_code status_code then
      error (f_"failed to download %s: HTTP status code %s") uri status_code;

    (* Now download the file. *)
    let curl_h =
      let curl_args = ref common_args in
      push_back curl_args ("output", Some filename_new);

      if not (verbose ()) then (
        if progress_bar then push_back curl_args ("progress-bar", None)
        else append curl_args quiet_args
      );

      Curl.create ~curl:t.curl ~tmpdir:t.tmpdir !curl_args in

    ignore (Curl.run curl_h)
  );

  (* Rename the file if the download was successful. *)
  rename filename_new filename
