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
class input_libvirt_xen_ssh libvirt_conn parsed_uri server guest =
object (self)
  inherit input_libvirt libvirt_conn guest

  method precheck () =
    if backend_is_libvirt () then
      error (f_"because of libvirt bug https://bugzilla.redhat.com/1140166 you must set this environment variable:\n\nexport LIBGUESTFS_BACKEND=direct\n\nand then rerun the virt-v2v command.");
    error_if_libvirt_does_not_support_json_backingfile ();
    error_if_no_ssh_agent ()

  method source () =
    debug "input_libvirt_xen_ssh: source: server %s" server;

    let source, disks, _ = parse_libvirt_domain self#conn guest in

    let port =
      match parsed_uri.uri_port with
      | 0 | 22 -> None
      | i -> Some (string_of_int i) in

    let user = parsed_uri.uri_user in

    (* Map the <source/> filename (which is relative to the remote
     * Xen server) to an ssh URI pointing to nbdkit.
     *)
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } ->
        disk
      | { p_source_disk = disk; p_source = P_source_dev path }
      | { p_source_disk = disk; p_source = P_source_file path } ->
         let nbdkit = Nbdkit.create_ssh ~password:NoPassword
                                        ?port ~server ?user path in
         let qemu_uri = Nbdkit.run nbdkit in
        { disk with s_qemu_uri = qemu_uri }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirt_xen_ssh = new input_libvirt_xen_ssh
