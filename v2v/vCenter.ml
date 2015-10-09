(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

open Common_utils
open Common_gettext.Gettext

open Xml

(* Memoized session cookie. *)
let session_cookie = ref ""

let get_session_cookie password scheme uri sslverify url =
  if !session_cookie <> "" then
    Some !session_cookie
  else (
    let curl_args = [
      "head", None;
      "silent", None;
      "url", Some url;
    ] in
    let curl_args =
      match uri.uri_user, password with
      | None, None -> curl_args
      | None, Some _ ->
         warning (f_"--password-file parameter ignored because 'user@' was not given in the URL");
         curl_args
      | Some user, None ->
         ("user", Some user) :: curl_args
      | Some user, Some password ->
         ("user", Some (user ^ ":" ^ password)) :: curl_args in
    let curl_args =
      if not sslverify then ("insecure", None) :: curl_args else curl_args in

    let lines = Curl.run curl_args in

    let dump_response chan =
      Curl.print_curl_command chan curl_args;

      (* Dump out the output of the command. *)
      List.iter (fun x -> fprintf chan "%s\n" x) lines;
      flush chan
    in

    if verbose () then dump_response stdout;

    (* Look for the last HTTP/x.y NNN status code in the output. *)
    let status = ref "" in
    List.iter (
      fun line ->
        let len = String.length line in
        if len >= 12 && String.sub line 0 5 = "HTTP/" then
          status := String.sub line 9 3
    ) lines;
    let status = !status in
    if status = "" then (
      dump_response stderr;
      error (f_"vcenter: no status code in output of 'curl' command.  Is 'curl' installed?")
    );

    if status = "401" then (
      dump_response stderr;
      if uri.uri_user <> None then
        error (f_"vcenter: incorrect username or password")
      else
        error (f_"vcenter: incorrect username or password.  You might need to specify the username in the URI like this: %s://USERNAME@[etc]")
              scheme
    );

    if status = "404" then (
      dump_response stderr;
      error (f_"vcenter: URL not found: %s\n\nThe '--dcpath' parameter may be useful.  See the explanation in the virt-v2v(1) man page OPTIONS section.") url
    );

    if status <> "200" then (
      dump_response stderr;
      error (f_"vcenter: invalid response from server")
    );

    (* Get the cookie. *)
    List.iter (
      fun line ->
        let len = String.length line in
        if len >= 12 && String.sub line 0 12 = "Set-Cookie: " then (
          let line = String.sub line 12 (len-12) in
          let cookie, _ = String.split ";" line in
          session_cookie := cookie
        )
    ) lines;
    if !session_cookie = "" then (
      dump_response stderr;
      warning (f_"vcenter: could not read session cookie from the vCenter Server, conversion may consume all sessions on the server and fail part way through");
      None
    )
    else
      Some !session_cookie
  )

let multiple_slash = Str.regexp "/+"
let default_dc = "ha-datacenter"

let guess_dcPath uri = function
  | "vpx" ->
     (match uri.uri_path with
      | None ->
         warning (f_"vcenter: URI (-ic parameter) contains no path, so we cannot determine the dcPath (datacenter name)");
         default_dc
      | Some path ->
         (* vCenter: URIs are *usually* '/Folder/Datacenter/esxi' so we can
          * just chop off the first '/' and final '/esxi' to get the dcPath.
          *
          * The libvirt driver allows things like '/DC///esxi////' so we also
          * have to handle trailing slashes and collapse multiple slashes into
          * single (RHBZ#1258342).
          *
          * However if there is a cluster involved then the URI may be
          * /Folder/Datacenter/Cluster/esxi but dcPath=Folder/Datacenter/Cluster
          * won't work.  In this case the user has to adjust the path to
          * remove the Cluster name (which still works in libvirt).  There
          * should be a way to ask the libvirt vpx driver for the correct
          * path, but there isn't. XXX  See also RHBZ#1256823.
          *)
         (* Collapse multiple slashes to single slash. *)
         let path = Str.global_replace multiple_slash "/" path in
         (* Chop off the first and trailing '/' (if found). *)
         let path =
           let len = String.length path in
           if len > 0 && path.[0] = '/' then
             String.sub path 1 (len-1)
           else path in
         let path =
           let len = String.length path in
           if len > 0 && path.[len-1] = '/' then
             String.sub path 0 (len-1)
           else path in
         (* Chop off the final element (ESXi hostname). *)
         let len =
           try String.rindex path '/' with Not_found -> String.length path in
         String.sub path 0 len
     );
  | "esx" -> (* Connecting to an ESXi hypervisor directly, so it's fixed. *)
     default_dc
  | _ ->     (* Don't know, so guess. *)
     default_dc
