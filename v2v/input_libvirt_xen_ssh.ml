(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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
open Tools_utils

open Types
open Xml
open Utils
open Parse_libvirt_xml
open Input_libvirt_other

open Printf

(* Subclass specialized for handling Xen over SSH. *)
class input_libvirt_xen_ssh input_conn input_password parsed_uri server guest =
object
  inherit input_libvirt input_conn input_password guest

  method precheck () =
    if backend_is_libvirt () then
      error (f_"because of libvirt bug https://bugzilla.redhat.com/1140166 you must set this environment variable:\n\nexport LIBGUESTFS_BACKEND=direct\n\nand then rerun the virt-v2v command.");
    error_if_libvirt_does_not_support_json_backingfile ();
    error_if_no_ssh_agent ()

  method source () =
    debug "input_libvirt_xen_ssh: source: server %s" server;

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Libvirt_utils.dumpxml ?password_file:input_password
                                    ?conn:input_conn guest in
    let source, disks = parse_libvirt_xml ?conn:input_conn xml in

    (* Map the <source/> filename (which is relative to the remote
     * Xen server) to an ssh URI.  This is a JSON URI looking something
     * like this:
     *
     * json: {
     *   "file.driver": "ssh",
     *   "file.user": "username",
     *   "file.host": "xen-host",
     *   "file.port": 1022,
     *   "file.path": <remote-path>,
     *   "file.host_key_check": "no"
     * }
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

        debug "ssh: json parameters: %s" (JSON.string_of_doc json_params);

        (* Turn the JSON parameters into a 'json:' protocol string. *)
        let qemu_uri = "json: " ^ JSON.string_of_doc json_params in

        { disk with s_qemu_uri = qemu_uri }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirt_xen_ssh = new input_libvirt_xen_ssh
