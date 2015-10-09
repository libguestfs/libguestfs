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

let map_source_to_uri ?readahead dcPath password uri scheme server path =
  if not (Str.string_match source_re path 0) then
    path
  else (
    let datastore = Str.matched_group 1 path
    and path = Str.matched_group 2 path in

    (* Get the dcPath. *)
    let dcPath =
      match dcPath with
      | None ->
         let dcPath = VCenter.guess_dcPath uri scheme in
         if verbose () then
           printf "vcenter: calculated dcPath as: %s\n" dcPath;
         dcPath
      | Some dcPath ->
         if verbose () then
           printf "vcenter: using --dcpath from the command line: %s\n" dcPath;
         dcPath in

    let port =
      match uri.uri_port with
      | 443 -> ""
      | n when n >= 1 -> ":" ^ string_of_int n
      | _ -> "" in

    let url =
      sprintf
        "https://%s%s/folder/%s-flat.vmdk?dcPath=%s&dsName=%s"
        server port
        (uri_quote path) (uri_quote dcPath) (uri_quote datastore) in

    (* If no_verify=1 was passed in the libvirt URI, then we have to
     * turn off certificate verification here too.
     *)
    let sslverify =
      match uri.uri_query_raw with
      | None -> true
      | Some query ->
        (* XXX only works if the query string is not URI-quoted *)
        String.find query "no_verify=1" = -1 in

    (* Now we have to query the server to get the session cookie. *)
    let session_cookie =
      VCenter.get_session_cookie password scheme uri sslverify url in

    (* Construct the JSON parameters. *)
    let json_params = [
      "file.driver", JSON.String "https";
      "file.url", JSON.String url;
      (* https://bugzilla.redhat.com/show_bug.cgi?id=1146007#c10 *)
      "file.timeout", JSON.Int 2000;
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

    if verbose () then
      printf "vcenter: json parameters: %s\n" (JSON.string_of_doc json_params);

    (* Turn the JSON parameters into a 'json:' protocol string.
     * Note this requires qemu-img >= 2.1.0.
     *)
    let qemu_uri = "json: " ^ JSON.string_of_doc json_params in

    qemu_uri
  )

(* Subclass specialized for handling VMware vCenter over https. *)
class input_libvirt_vcenter_https
  dcPath password libvirt_uri parsed_uri scheme server guest =
object
  inherit input_libvirt password libvirt_uri guest

  val saved_source_paths = Hashtbl.create 13

  method source () =
    if verbose () then
      printf "input_libvirt_vcenter_https: source: scheme %s server %s\n%!"
        scheme server;

    error_if_libvirt_backend ();

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Domainxml.dumpxml ?password ?conn:libvirt_uri guest in
    let source, disks = parse_libvirt_xml ?conn:libvirt_uri xml in

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
	                                 dcPath password
                                         parsed_uri scheme server path in

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
                          dcPath password
                          parsed_uri scheme server orig_path in

      (* Rebase the qcow2 overlay to adjust the readahead parameter. *)
      let cmd =
        sprintf "qemu-img rebase -u -b %s %s"
          (quote backing_qemu_uri) (quote overlay.ov_overlay_file) in
      if verbose () then printf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then
        warning (f_"qemu-img rebase failed (ignored)")
end

let input_libvirt_vcenter_https = new input_libvirt_vcenter_https
