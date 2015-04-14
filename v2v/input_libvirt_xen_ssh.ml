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

(** [-i libvirt] when the source is Xen *)

open Common_gettext.Gettext
open Common_utils

open Types
open Xml
open Utils
open Input_libvirtxml
open Input_libvirt_other

open Printf

(* Subclass specialized for handling Xen over SSH. *)
class input_libvirt_xen_ssh verbose password libvirt_uri parsed_uri scheme server guest =
object
  inherit input_libvirt verbose password libvirt_uri guest

  method source () =
    if verbose then
      printf "input_libvirt_xen_ssh: source: scheme %s server %s\n%!"
        scheme server;

    error_if_libvirt_backend ();
    error_if_no_ssh_agent ();

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Domainxml.dumpxml ?password ?conn:libvirt_uri guest in
    let source, disks = parse_libvirt_xml ?conn:libvirt_uri ~verbose xml in

    (* Map the <source/> filename (which is relative to the remote
     * Xen server) to an ssh URI.  This is a JSON URI looking something
     * like this:
     *
     * json: {
     *   "file.driver": "ssh",
     *   "file.user": "username",
     *   "file.host": "xen-host",
     *   "file.port": 1022,
     *   "file.path": "path",
     *   "file.host_key_check": "no"
     *)
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } ->
        disk
      | { p_source_disk = disk; p_source = P_source_dev path }
      | { p_source_disk = disk; p_source = P_source_file path } ->
        (* Construct the JSON parameters. *)
        let json_params = [
          "file.driver", JSON.String "ssh";
          "file.path", JSON.String path;
          "file.host", JSON.String server;
          "file.host_key_check", JSON.String "no";
        ] in

        let json_params =
          match parsed_uri.uri_port with
          | 0 | 22 -> json_params
          (* qemu will actually assert-fail if you send the port
           * number as a string ...
           *)
          | i -> ("file.port", JSON.Int i) :: json_params in

        let json_params =
          match parsed_uri.uri_user with
          | None -> json_params
          | Some user -> ("file.user", JSON.String user) :: json_params in

        if verbose then
          printf "ssh: json parameters: %s\n" (JSON.string_of_doc json_params);

        (* Turn the JSON parameters into a 'json:' protocol string. *)
        let qemu_uri = "json: " ^ JSON.string_of_doc json_params in

        { disk with s_qemu_uri = qemu_uri }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirt_xen_ssh = new input_libvirt_xen_ssh
