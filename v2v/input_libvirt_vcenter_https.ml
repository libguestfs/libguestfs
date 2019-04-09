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

(** [-i libvirt] when the source is VMware vCenter *)

open Common_gettext.Gettext
open Tools_utils
open Unix_utils.Env

open Types
open Utils
open Xpath_helpers
open Parse_libvirt_xml
open Input_libvirt_other

open Printf

(* Subclass specialized for handling VMware vCenter over https. *)
class input_libvirt_vcenter_https
        libvirt_conn input_password parsed_uri server guest =
object (self)
  inherit input_libvirt libvirt_conn guest

  val mutable dcPath = ""

  method precheck () =
    error_if_libvirt_does_not_support_json_backingfile ()

  method source ?bandwidth () =
    debug "input_libvirt_vcenter_https: source: server %s" server;

    (* Remove proxy environment variables so curl doesn't try to use
     * them.  Using a proxy is generally a bad idea because vCenter
     * is slow enough as it is without putting another device in
     * the way (RHBZ#1354507).
     *)
    unsetenv "https_proxy";
    unsetenv "all_proxy";
    unsetenv "no_proxy";
    unsetenv "HTTPS_PROXY";
    unsetenv "ALL_PROXY";
    unsetenv "NO_PROXY";

    let source, disks, xml = parse_libvirt_domain ?bandwidth self#conn guest in

    (* Find the <vmware:datacenterpath> element from the XML.  This
     * was added in libvirt >= 1.2.20.
     *)
    dcPath <- (
      let doc = Xml.parse_memory xml in
      let xpathctx = Xml.xpath_new_context doc in
      Xml.xpath_register_ns xpathctx
        "vmware" "http://libvirt.org/schemas/domain/vmware/1.0";
      match xpath_string xpathctx "/domain/vmware:datacenterpath" with
      | Some dcPath -> dcPath
      | None ->
         error (f_"vcenter: <vmware:datacenterpath> was not found in the XML.  You need to upgrade to libvirt ≥ 1.2.20.")
    );

    let disks = List.map (
      function
      | { p_source = P_source_dev _ } -> assert false
      | { p_source_disk = disk; p_source = P_dont_rewrite } -> disk
      | { p_source_disk = disk; p_source = P_source_file path } ->
        let { VCenter.qemu_uri } =
          VCenter.map_source ?bandwidth ?password_file:input_password
                             dcPath parsed_uri server path in

        (* The libvirt ESX driver doesn't normally specify a format, but
         * the format of the -flat file is *always* raw, so force it here.
         *)
        { disk with s_qemu_uri = qemu_uri; s_format = Some "raw" }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirt_vcenter_https = new input_libvirt_vcenter_https
