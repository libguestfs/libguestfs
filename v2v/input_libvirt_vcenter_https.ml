(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** [-i libvirt] when the source is VMware vCenter *)

open Common_gettext.Gettext
open Common_utils

open Types
open Xml
open Utils
open Input_libvirtxml
open Input_libvirt_other

open Printf

(* See RHBZ#1151033 and RHBZ#1153589. *)
let readahead_for_conversion = None
let readahead_for_copying = Some (64 * 1024 * 1024)

(* Return the session cookie.  It is memoized, so you can call this
 * as often as required.
 *)
let rec get_session_cookie =
  let session_cookie = ref "" in
  fun verbose password scheme uri sslverify url ->
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
          warning ~prog (f_"--password-file parameter ignored because 'user@' was not given in the URL");
          curl_args
        | Some user, None ->
          ("user", Some user) :: curl_args
        | Some user, Some password ->
          ("user", Some (user ^ ":" ^ password)) :: curl_args in
      let curl_args =
        if not sslverify then ("insecure", None) :: curl_args else curl_args in

      let lines = run_curl_get_lines curl_args in

      let dump_response chan =
        (* Don't print passwords in the debug output. *)
        let curl_args =
          List.map (
            function
            | ("user", Some _) -> ("user", Some "<hidden>")
            | x -> x
          ) curl_args in
        (* Dump out the approximate curl command that was run. *)
        fprintf chan "curl -q";
        List.iter (
          function
          | name, None -> fprintf chan " --%s" name
          | name, Some value -> fprintf chan " --%s %s" name (quote value)
        ) curl_args;
        fprintf chan "\n";
        (* Dump out the output of the command. *)
        List.iter (fun x -> fprintf chan "%s\n" x) lines;
        flush chan
      in

      if verbose then dump_response stdout;

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
        error (f_"vcenter: URL not found: %s") url
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
            let cookie, _ = string_split ";" line in
            session_cookie := cookie
          )
      ) lines;
      if !session_cookie = "" then (
        dump_response stderr;
        warning ~prog (f_"vcenter: could not read session cookie from the vCenter Server, conversion may consume all sessions on the server and fail part way through");
        None
      )
      else
        Some !session_cookie
    )

(* Run 'curl' and pass the arguments securely through the --config
 * option and an external file.
 *)
and run_curl_get_lines curl_args =
  let config_file, chan = Filename.open_temp_file "v2vcurl" ".conf" in
  List.iter (
    function
    | name, None -> fprintf chan "%s\n" name
    | name, Some value ->
      fprintf chan "%s = \"" name;
      (* Write the quoted value.  See 'curl' man page for what is
       * allowed here.
       *)
      let len = String.length value in
      for i = 0 to len-1 do
        match value.[i] with
        | '\\' -> output_string chan "\\\\"
        | '"' -> output_string chan "\\\""
        | '\t' -> output_string chan "\\t"
        | '\n' -> output_string chan "\\n"
        | '\r' -> output_string chan "\\r"
        | '\x0b' -> output_string chan "\\v"
        | c -> output_char chan c
      done;
      fprintf chan "\"\n"
  ) curl_args;
  close_out chan;

  let cmd = sprintf "curl -q --config %s" (quote config_file) in
  let lines = external_command ~prog cmd in
  Unix.unlink config_file;
  lines

(* Helper function to extract the datacenter from a URI. *)
let get_datacenter uri scheme =
  let default_dc = "ha-datacenter" in
  match scheme with
  | "vpx" ->           (* Hopefully the first part of the path. *)
    (match uri.uri_path with
    | None ->
      warning ~prog (f_"vcenter: URI (-ic parameter) contains no path, so we cannot determine the datacenter name");
      default_dc
    | Some path ->
      let path =
        let len = String.length path in
        if len > 0 && path.[0] = '/' then
          String.sub path 1 (len-1)
        else path in
      let len =
        try String.index path '/' with Not_found -> String.length path in
      String.sub path 0 len
    );
  | "esx" -> (* Connecting to an ESXi hypervisor directly, so it's fixed. *)
    default_dc
  | _ ->                            (* Don't know, so guess. *)
    default_dc

(* Map the <source/> string to a qemu URI using the cURL driver
 * in qemu.  The 'path' will be something like
 *
 *   "[datastore1] Fedora 20/Fedora 20.vmdk"
 *
 * including those literal spaces in the string.
 *
 * XXX Old virt-v2v could also handle snapshots, ie:
 *
 *   "[datastore1] Fedora 20/Fedora 20-NNNNNN.vmdk"
 *
 * XXX Need to handle templates.  The file is called "-delta.vmdk" in
 * place of "-flat.vmdk".
 *)
let source_re = Str.regexp "^\\[\\(.*\\)\\] \\(.*\\)\\.vmdk$"

let map_source_to_uri ?readahead verbose password uri scheme server path =
  if not (Str.string_match source_re path 0) then
    path
  else (
    let datastore = Str.matched_group 1 path
    and path = Str.matched_group 2 path in

    (* Get the datacenter. *)
    let datacenter = get_datacenter uri scheme in

    let port =
      match uri.uri_port with
      | 443 -> ""
      | n when n >= 1 -> ":" ^ string_of_int n
      | _ -> "" in

    let url =
      sprintf
        "https://%s%s/folder/%s-flat.vmdk?dcPath=%s&dsName=%s"
        server port
        (uri_quote path) (uri_quote datacenter) (uri_quote datastore) in

    (* If no_verify=1 was passed in the libvirt URI, then we have to
     * turn off certificate verification here too.
     *)
    let sslverify =
      match uri.uri_query_raw with
      | None -> true
      | Some query ->
        (* XXX only works if the query string is not URI-quoted *)
        string_find query "no_verify=1" = -1 in

    (* Now we have to query the server to get the session cookie. *)
    let session_cookie =
      get_session_cookie verbose password scheme uri sslverify url in

    (* Construct the JSON parameters. *)
    let json_params = [
      "file.driver", JSON.String "https";
      "file.url", JSON.String url;
      "file.timeout", JSON.Int 600;
    ] in

    let json_params =
      match readahead with
      | None -> json_params
      | Some readahead ->
        ("file.readahead", JSON.Int readahead) :: json_params in

    let json_params =
      if sslverify then json_params
      else ("file.sslverify", JSON.String "off") :: json_params in

    let json_params =
      match session_cookie with
      | None -> json_params
      | Some cookie -> ("file.cookie", JSON.String cookie) :: json_params in

    if verbose then
      printf "vcenter: json parameters: %s\n" (JSON.string_of_doc json_params);

    (* Turn the JSON parameters into a 'json:' protocol string.
     * Note this requires qemu-img >= 2.1.0.
     *)
    let qemu_uri = "json: " ^ JSON.string_of_doc json_params in

    qemu_uri
  )

(* Subclass specialized for handling VMware vCenter over https. *)
class input_libvirt_vcenter_https
  verbose password libvirt_uri parsed_uri scheme server guest =
object
  inherit input_libvirt verbose password libvirt_uri guest

  val saved_source_paths = Hashtbl.create 13

  method source () =
    if verbose then
      printf "input_libvirt_vcenter_https: source: scheme %s server %s\n%!"
        scheme server;

    error_if_libvirt_backend ();

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Domainxml.dumpxml ?password ?conn:libvirt_uri guest in
    let source, disks = parse_libvirt_xml ?conn:libvirt_uri ~verbose xml in

    (* Save the original source paths, so that we can remap them again
     * in [#adjust_overlay_parameters].
     *)
    List.iter (
      function
      | { p_source = P_source_dev _ } ->
        (* Should never happen ... *)
        error (f_"source disk has <source dev=...> attribute in XML")
      | { p_source_disk = { s_disk_id = id }; p_source = P_dont_rewrite } ->
        Hashtbl.add saved_source_paths id None
      | { p_source_disk = { s_disk_id = id }; p_source = P_source_file path } ->
        Hashtbl.add saved_source_paths id (Some path)
    ) disks;

    let readahead = readahead_for_conversion in
    let disks = List.map (
      function
      | { p_source = P_source_dev _ } -> assert false
      | { p_source_disk = disk; p_source = P_dont_rewrite } -> disk
      | { p_source_disk = disk; p_source = P_source_file path } ->
        let qemu_uri = map_source_to_uri ?readahead
	  verbose password parsed_uri scheme server path in

        (* The libvirt ESX driver doesn't normally specify a format, but
         * the format of the -flat file is *always* raw, so force it here.
         *)
        { disk with s_qemu_uri = qemu_uri; s_format = Some "raw" }
    ) disks in

    { source with s_disks = disks }

  (* See RHBZ#1151033 and RHBZ#1153589 for why this is necessary. *)
  method adjust_overlay_parameters overlay =
    let orig_path =
      try Hashtbl.find saved_source_paths overlay.ov_source.s_disk_id
      with Not_found -> failwith "internal error in adjust_overlay_parameters" in
    match orig_path with
    | None -> ()
    | Some orig_path ->
      let readahead = readahead_for_copying in
      let backing_qemu_uri =
        map_source_to_uri ?readahead
          verbose password parsed_uri scheme server orig_path in

      (* Rebase the qcow2 overlay to adjust the readahead parameter. *)
      let cmd =
        sprintf "qemu-img rebase -u -b %s %s"
          (quote backing_qemu_uri) (quote overlay.ov_overlay_file) in
      if verbose then printf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then
        warning ~prog (f_"qemu-img rebase failed (ignored)")
end

let input_libvirt_vcenter_https = new input_libvirt_vcenter_https
