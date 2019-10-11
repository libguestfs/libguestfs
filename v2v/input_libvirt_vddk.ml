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

(** [-i libvirt] when the source is VMware via nbdkit vddk plugin *)

open Common_gettext.Gettext
open Tools_utils
open Std_utils
open Unix_utils

open Types
open Utils
open Input_libvirt_other
open Parse_libvirt_xml
open Xpath_helpers

open Printf

type vddk_options = (string * string) list

(* List of vddk-* input options. *)
let vddk_option_keys =
  [ "config";
    "cookie";
    "libdir";
    "nfchostport";
    "port";
    "snapshot";
    "thumbprint";
    "transports" ]

let print_input_options () =
  printf (f_"Input options (-io) which can be used with -it vddk:

  -io vddk-thumbprint=xx:xx:xx:...
                               VDDK server thumbprint (required)

All other settings are optional:

  -io vddk-config=FILE         VDDK configuration file
  -io vddk-cookie=COOKIE       VDDK cookie
  -io vddk-libdir=LIBDIR       VDDK library parent directory
  -io vddk-nfchostport=PORT    VDDK nfchostport
  -io vddk-port=PORT           VDDK port
  -io vddk-snapshot=SNAPSHOT-MOREF
                               VDDK snapshot moref
  -io vddk-transports=MODE:MODE:..
                               VDDK transports

Refer to nbdkit-vddk-plugin(1) and the VDDK documentation for further
information on these settings.
")

let parse_input_options options =
  (* Check there are no options we don't understand.  Also removes
   * the "vddk-" prefix from the internal list.
   *)
  let options =
    List.map (
      fun (key, value) ->
        let error_invalid_key () =
          error (f_"-it vddk: ‘-io %s’ is not a valid input option") key
        in
        if not (String.is_prefix key "vddk-") then error_invalid_key ();
        let key = String.sub key 5 (String.length key-5) in
        if not (List.mem key vddk_option_keys) then error_invalid_key ();

        (key, value)
    ) options in

  (* Check no option appears more than once. *)
  let keys = List.map fst options in
  if List.length keys <> List.length (List.sort_uniq keys) then
    error (f_"-it vddk: duplicate -io options on the command line");

  options

(* Subclass specialized for handling VMware via nbdkit vddk plugin. *)
class input_libvirt_vddk libvirt_conn input_conn input_password vddk_options
                         parsed_uri guest =
  let error_unless_thumbprint () =
    if not (List.mem_assoc "thumbprint" vddk_options) then
      error (f_"You must pass the ‘-io vddk-thumbprint’ option with the SSL thumbprint of the VMware server.  To find the thumbprint, see the nbdkit-vddk-plugin(1) manual.  See also the virt-v2v-input-vmware(1) manual.")
  in

object (self)
  inherit input_libvirt libvirt_conn guest as super

  method precheck () =
    error_unless_thumbprint ()

  method as_options =
    let pt_options =
      String.concat ""
                    (List.map (fun (k, v) ->
                         sprintf " -io vddk-%s=%s" k v) vddk_options) in
    sprintf "%s -it vddk %s"
            super#as_options (* superclass prints "-i libvirt etc" *)
            pt_options

  method source ?bandwidth () =
    let source, disks, xml = parse_libvirt_domain ?bandwidth self#conn guest in

    (* Find the <vmware:moref> element from the XML.  This was added
     * in libvirt >= 3.7 and is required.
     *)
    let moref =
      let doc = Xml.parse_memory xml in
      let xpathctx = Xml.xpath_new_context doc in
      Xml.xpath_register_ns xpathctx
        "vmware" "http://libvirt.org/schemas/domain/vmware/1.0";
      let xpath_string = xpath_string xpathctx in
      match xpath_string "/domain/vmware:moref" with
      | Some moref -> moref
      | None ->
         error (f_"<vmware:moref> was not found in the output of ‘virsh dumpxml \"%s\"’.  The most likely reason is that libvirt is too old, try upgrading libvirt to ≥ 3.7.") guest in

    (* It probably never happens that the server name can be missing
     * from the libvirt URI, but we need a server name to pass to
     * nbdkit, so ...
     *)
    let server =
      match parsed_uri.Xml.uri_server with
      | Some server -> server
      | None ->
         match input_conn with
         | Some input_conn ->
            error (f_"‘-ic %s’ URL does not contain a host name field")
                  input_conn
         | None ->
            error (f_"you must use the ‘-ic’ parameter.  See the virt-v2v-input-vmware(1) manual.") in

    let user = parsed_uri.Xml.uri_user in

    let config =
      try Some (List.assoc "config" vddk_options) with Not_found -> None in
    let cookie =
      try Some (List.assoc "cookie" vddk_options) with Not_found -> None in
    let libdir =
      try Some (List.assoc "libdir" vddk_options) with Not_found -> None in
    let nfchostport =
      try Some (List.assoc "nfchostport" vddk_options) with Not_found -> None in
    let port =
      try Some (List.assoc "port" vddk_options) with Not_found -> None in
    let snapshot =
      try Some (List.assoc "snapshot" vddk_options) with Not_found -> None in
    let thumbprint =
      try List.assoc "thumbprint" vddk_options
      with Not_found -> assert false (* checked in precheck method *) in
    let transports =
      try Some (List.assoc "transports" vddk_options) with Not_found -> None in

    (* Create an nbdkit instance for each disk and rewrite the source
     * paths to point to the NBD socket.
     *)
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } ->
         disk

      | { p_source = P_source_dev _ } -> (* Should never happen. *)
         error (f_"source disk has <source dev=...> attribute in XML")

      | { p_source_disk = disk; p_source = P_source_file path } ->
         (* The <source file=...> attribute returned by the libvirt
          * VMX driver looks like "[datastore] path".  We can use it
          * directly as the nbdkit file= parameter, and it is passed
          * directly in this form to VDDK.
          *)
         let nbdkit =
           Nbdkit.create_vddk ?bandwidth ?config ?cookie ?libdir ~moref
                              ?nfchostport ?password_file:input_password ?port
                              ~server ?snapshot ~thumbprint ?transports ?user
                              path in
         let qemu_uri = Nbdkit.run nbdkit in

         (* nbdkit always presents us with the raw disk blocks from
          * the guest, so force the format to raw here.
          *)
         { disk with s_qemu_uri = qemu_uri; s_format = Some "raw" }
    ) disks in

    source, disks
end

let input_libvirt_vddk = new input_libvirt_vddk
