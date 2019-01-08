(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Xml
open Utils

type remote_resource = {
  https_url : string;
  qemu_uri : string;
  session_cookie : string option;
  sslverify : bool;
}

let source_re = PCRE.compile "^\\[(.*)\\] (.*)\\.vmdk$"
let snapshot_re = PCRE.compile "^(.*)-\\d{6}(\\.vmdk)$"

let rec map_source ?readahead ?password_file dcPath uri server path =
  (* If no_verify=1 was passed in the libvirt URI, then we have to
   * turn off certificate verification here too.
   *)
  let sslverify =
    match uri.uri_query_raw with
    | None -> true
    | Some query ->
       (* XXX only works if the query string is not URI-quoted *)
       String.find query "no_verify=1" = -1 in

  let https_url =
    let https_url = get_https_url dcPath uri server path in
    (* Check the URL exists. *)
    let status, _, _ =
      fetch_headers_from_url password_file uri sslverify https_url in
    (* If a disk is actually a snapshot image it will have '-00000n'
     * appended to its name, e.g.:
     *   [yellow:storage1] RHEL4-X/RHEL4-X-000003.vmdk
     * The flat storage is still called RHEL4-X-flat, however. If we got
     * a 404 and the vmdk name looks like it might be a snapshot, try
     * again without the snapshot suffix.
     *)
    if status = "404" && PCRE.matches snapshot_re path then (
      let path = PCRE.sub 1 ^ PCRE.sub 2 in
      get_https_url dcPath uri server path
    )
    else
      (* Note that other non-200 status errors will be handled
       * in get_session_cookie below, so we don't have to worry
       * about them here.
       *)
      https_url in

  let session_cookie =
    get_session_cookie password_file uri sslverify https_url in

  let qemu_uri =
    (* Construct the JSON parameters for the qemu URI. *)
    let json_params = [
      "file.driver", JSON.String "https";
      "file.url", JSON.String https_url;
      (* https://bugzilla.redhat.com/show_bug.cgi?id=1146007#c10 *)
      "file.timeout", JSON.Int 2000_L;
    ] in

    let json_params =
      match readahead with
      | None -> json_params
      | Some readahead ->
         ("file.readahead", JSON.Int (Int64.of_int readahead)) :: json_params in

    let json_params =
      if sslverify then json_params
      else ("file.sslverify", JSON.String "off") :: json_params in

    let json_params =
      match session_cookie with
      | None -> json_params
      | Some cookie -> ("file.cookie", JSON.String cookie) :: json_params in

    debug "vcenter: json parameters: %s" (JSON.string_of_doc json_params);

    (* Turn the JSON parameters into a 'json:' protocol string.
     * Note this requires qemu-img >= 2.1.0.
     *)
    let qemu_uri = "json: " ^ JSON.string_of_doc json_params in

    qemu_uri in

  (* Return the struct. *)
  { https_url = https_url;
    qemu_uri = qemu_uri;
    session_cookie = session_cookie;
    sslverify = sslverify }

and get_https_url dcPath uri server path =
  if not (PCRE.matches source_re path) then
    path
  else (
    let datastore = PCRE.sub 1 and path = PCRE.sub 2 in

    let port =
      match uri.uri_port with
      | 443 -> ""
      | n when n >= 1 -> ":" ^ string_of_int n
      | _ -> "" in

    (* XXX Need to handle templates.  The file is called "-delta.vmdk" in
     * place of "-flat.vmdk".
     *)
    sprintf "https://%s%s/folder/%s-flat.vmdk?dcPath=%s&dsName=%s"
            server port
            (uri_quote path) (uri_quote dcPath) (uri_quote datastore)
  )

and get_session_cookie password_file uri sslverify https_url =
  let status, headers, dump_response =
    fetch_headers_from_url password_file uri sslverify https_url in

  if status = "401" then (
    dump_response stderr;
    if uri.uri_user <> None then
      error (f_"vcenter: incorrect username or password")
    else
      error (f_"vcenter: incorrect username or password.  You might need to specify the username in the URI like this: [vpx|esx|..]://USERNAME@[etc]")
  );

  if status = "404" then (
    dump_response stderr;
    error (f_"vcenter: URL not found: %s") https_url
  );

  if status <> "200" then (
    dump_response stderr;
    error (f_"vcenter: invalid response from server")
  );

  (* Get the cookie. *)
  let rec loop = function
    | [] ->
       dump_response stderr;
       warning (f_"vcenter: could not read session cookie from the vCenter Server, conversion may consume all sessions on the server and fail part way through");
       None
    | ("set-cookie", cookie) :: _ ->
       let cookie, _ = String.split ";" cookie in
       Some cookie

    | _ :: headers ->
       loop headers
  in
  loop headers

(* Fetch the status and reply headers from a URL. *)
and fetch_headers_from_url password_file uri sslverify https_url =
  let curl_args = ref [
    "head", None;
    "silent", None;
    "url", Some https_url;
  ] in
  (match uri.uri_user, password_file with
   | None, None -> ()
   | None, Some _ ->
      warning (f_"-ip PASSWORD_FILE parameter ignored because 'user@' was not given in the URL")
   | Some user, None ->
      List.push_back curl_args ("user", Some user)
   | Some user, Some password_file ->
      let password = read_first_line_from_file password_file in
      List.push_back curl_args ("user", Some (user ^ ":" ^ password))
  );
  if not sslverify then List.push_back curl_args ("insecure", None);

  let curl_h = Curl.create !curl_args in
  let lines = Curl.run curl_h in

  let dump_response chan =
    Curl.print chan curl_h;

    (* Dump out the output of the command. *)
    List.iter (fun x -> fprintf chan "%s\n" x) lines;
    flush chan
  in

  if verbose () then dump_response stderr;

  let statuses, headers =
    List.partition (
      fun line ->
        let len = String.length line in
        len >= 12 && String.sub line 0 5 = "HTTP/"
    ) lines in

  (* Look for the last HTTP/x.y NNN status code in the output. *)
  let status =
    match statuses with
    | [] ->
       dump_response stderr;
       error (f_"vcenter: no status code in output of ‘curl’ command.  Is ‘curl’ installed?")
    | ss -> String.sub (List.hd (List.rev ss)) 9 3 in

  let headers =
    List.map (
      fun header ->
        let h, c = String.split ": " header in
        String.lowercase_ascii h, c
    ) headers in

  status, headers, dump_response
