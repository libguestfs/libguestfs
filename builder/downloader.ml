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

open Utils

open Unix
open Printf

type uri = string
type filename = string

type t = {
  curl : string;
  cache : Cache.t option;               (* cache for templates *)
}

type proxy_mode =
  | UnsetProxy
  | SystemProxy
  | ForcedProxy of string

let create ~curl ~cache = {
  curl = curl;
  cache = cache;
}

let rec download t ?template ?progress_bar ?(proxy = SystemProxy) uri =
  match template with
  | None ->                       (* no cache, simple download *)
    (* Create a temporary name. *)
    let tmpfile = Filename.temp_file "vbcache" ".txt" in
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
    with Invalid_argument "URI.parse_uri" ->
      error (f_"error parsing URI '%s'. Look for error messages printed above.")
        uri in

  (* Note because there may be parallel virt-builder instances running
   * and also to avoid partial downloads in the cache if the network
   * fails, we download to a random name in the cache and then
   * atomically rename it to the final filename.
   *)
  let filename_new = filename ^ "." ^ string_random8 () in
  unlink_on_exit filename_new;

  (match parseduri.URI.protocol with
  | "file" ->
    let path = parseduri.URI.path in
    let cmd = sprintf "cp%s %s %s"
      (if verbose () then " -v" else "")
      (quote path) (quote filename_new) in
    let r = Sys.command cmd in
    if r <> 0 then
      error (f_"cp (download) command failed copying '%s'") path;
  | _ as protocol -> (* Any other protocol. *)
    let outenv = proxy_envvar protocol proxy in
    (* Get the status code first to ensure the file exists. *)
    let cmd = sprintf "%s%s%s -L --max-redirs 5 -g -o /dev/null -I -w '%%{http_code}' %s"
      outenv
      t.curl
      (if verbose () then "" else " -s -S")
      (quote uri) in
    if verbose () then printf "%s\n%!" cmd;
    let lines = external_command cmd in
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
    let cmd = sprintf "%s%s%s -L --max-redirs 5 -g -o %s %s"
      outenv
      t.curl
      (if verbose () then "" else if progress_bar then " -#" else " -s -S")
      (quote filename_new) (quote uri) in
    if verbose () then printf "%s\n%!" cmd;
    let r = Sys.command cmd in
    if r <> 0 then
      error (f_"curl (download) command failed downloading '%s'") uri;
  );

  (* Rename the file if the download was successful. *)
  rename filename_new filename

and proxy_envvar protocol = function
  | UnsetProxy ->
    (match protocol with
    | "http" -> "env http_proxy= no_proxy=* "
    | "https" -> "env https_proxy= no_proxy=* "
    | "ftp" -> "env ftp_proxy= no_proxy=* "
    | _ -> "env no_proxy=* "
    )
  | SystemProxy ->
    (* No changes required. *)
    ""
  | ForcedProxy proxy ->
    let proxy = quote proxy in
    (match protocol with
    | "http" -> sprintf "env http_proxy=%s no_proxy= " proxy
    | "https" -> sprintf "env https_proxy=%s no_proxy= " proxy
    | "ftp" -> sprintf "env ftp_proxy=%s no_proxy= " proxy
    | _ -> ""
    )
