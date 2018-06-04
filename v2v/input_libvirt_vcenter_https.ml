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

(* See RHBZ#1151033 and RHBZ#1153589. *)
let readahead_for_conversion = None
let readahead_for_copying = Some (64 * 1024 * 1024)

(* Subclass specialized for handling VMware vCenter over https. *)
class input_libvirt_vcenter_https
        input_password libvirt_uri parsed_uri server guest =
object
  inherit input_libvirt input_password libvirt_uri guest

  val saved_source_paths = Hashtbl.create 13
  val mutable dcPath = ""

  method precheck () =
    error_if_libvirt_does_not_support_json_backingfile ()

  method source () =
    debug "input_libvirt_vcenter_https: source: server %s" server;

    (* Remove proxy environment variables so curl doesn't try to use
     * them.  Libvirt doesn't use the proxy anyway, and using a proxy
     * is generally a bad idea because vCenter is slow enough as it is
     * without putting another device in the way (RHBZ#1354507).
     *)
    unsetenv "https_proxy";
    unsetenv "all_proxy";
    unsetenv "no_proxy";
    unsetenv "HTTPS_PROXY";
    unsetenv "ALL_PROXY";
    unsetenv "NO_PROXY";

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Libvirt_utils.dumpxml ?password_file:input_password
                                    ?conn:libvirt_uri guest in
    let source, disks = parse_libvirt_xml ?conn:libvirt_uri xml in

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
        let { VCenter.qemu_uri } =
          VCenter.map_source ?readahead ?password_file:input_password
                             dcPath parsed_uri server path in

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
      let { VCenter.qemu_uri = backing_qemu_uri } =
        VCenter.map_source ?readahead ?password_file:input_password
                           dcPath parsed_uri server orig_path in

      (* Rebase the qcow2 overlay to adjust the readahead parameter. *)
      let cmd = [ "qemu-img"; "rebase"; "-u"; "-b"; backing_qemu_uri;
                  overlay.ov_overlay_file ] in
      if run_command cmd <> 0 then
        warning (f_"qemu-img rebase failed (ignored)")
end

let input_libvirt_vcenter_https = new input_libvirt_vcenter_https
