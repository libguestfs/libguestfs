(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(* Parse OVF from an externally produced OVA file. *)

open Std_utils
open Tools_utils
open Unix_utils
open Common_gettext.Gettext

open Types
open Utils
open Xpath_helpers

open Printf

type ovf_disk = {
  source_disk : Types.source_disk;
  href : string;                (* The <File href> from the OVF file. *)
  compressed : bool;            (* If the file is gzip compressed. *)
}

let parse_ovf_from_ova ovf_filename =
  let xml = read_whole_file ovf_filename in
  let doc = Xml.parse_memory xml in

  (* Handle namespaces. *)
  let xpathctx = Xml.xpath_new_context doc in
  Xml.xpath_register_ns xpathctx
                        "ovf" "http://schemas.dmtf.org/ovf/envelope/1";
  Xml.xpath_register_ns xpathctx
                        "rasd" "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData";
  Xml.xpath_register_ns xpathctx
                        "vmw" "http://www.vmware.com/schema/ovf";
  Xml.xpath_register_ns xpathctx
                        "vssd" "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData";

  let xpath_string = xpath_string xpathctx
  and xpath_int = xpath_int xpathctx
  and xpath_int64 = xpath_int64 xpathctx in

  let rec parse_top () =
    (* Search for vm name. *)
    let name =
      match xpath_string "/ovf:Envelope/ovf:VirtualSystem/ovf:Name/text()" with
      | None | Some "" -> None
      | Some _ as name -> name in

    (* Search for memory. *)
    let memory = Option.default (1024L *^ 1024L) (xpath_int64 "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=4]/rasd:VirtualQuantity/text()") in
    let memory = memory *^ 1024L *^ 1024L in

    (* Search for number of vCPUs. *)
    let vcpu = Option.default 1 (xpath_int "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=3]/rasd:VirtualQuantity/text()") in

    (* CPU topology.  coresPerSocket is a VMware proprietary extension.
     * I couldn't find out how hyperthreads is specified in the OVF.
     *)
    let cores_per_socket = xpath_int "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=3]/vmw:CoresPerSocket/text()" in
    let cpu_sockets, cpu_cores =
      match cores_per_socket with
      | None -> None, None
      | Some cores_per_socket when cores_per_socket <= 0 ->
         warning (f_"invalid vmw:CoresPerSocket (%d) ignored")
                 cores_per_socket;
         None, None
      | Some cores_per_socket ->
         let sockets = vcpu / cores_per_socket in
         if sockets <= 0 then (
           warning (f_"invalid vmw:CoresPerSocket < number of cores");
           None, None
         )
         else
           Some sockets, Some cores_per_socket in

    (* BIOS or EFI firmware? *)
    let firmware = Option.default "bios" (xpath_string "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/vmw:Config[@vmw:key=\"firmware\"]/@vmw:value") in
    let firmware =
      match firmware with
      | "bios" -> BIOS
      | "efi" -> UEFI
      | s ->
         error (f_"unknown Config:firmware value %s (expected \"bios\" or \"efi\")") s in

    name, memory, vcpu, cpu_sockets, cpu_cores, firmware,
    parse_disks (), parse_removables (), parse_nics ()

  (* Helper function to return the parent controller of a disk. *)
  and parent_controller id =
    let expr = sprintf "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:InstanceID/text()=%d]/rasd:ResourceType/text()" id in
    let controller = xpath_int expr in

    (* 5: IDE, 6: SCSI controller, 20: SATA *)
    match controller with
    | Some 5 -> Some Source_IDE
    | Some 6 -> Some Source_SCSI
    | Some 20 -> Some Source_SATA
    | None ->
       warning (f_"ova disk has no parent controller, please report this as a bug supplying the *.ovf file extracted from the ova");
       None
    | Some controller ->
       warning (f_"ova disk has an unknown VMware controller type (%d), please report this as a bug supplying the *.ovf file extracted from the ova")
               controller;
       None

  (* Hard disks (ResourceType = 17). *)
  and parse_disks () =
    let disks = ref [] in
    let expr = "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=17]" in
    let obj = Xml.xpath_eval_expression xpathctx expr in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let n = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx n;

      (* XXX We assume the OVF lists these in order.
         let address = xpath_int "rasd:AddressOnParent/text()" in
       *)

      (* Find the parent controller. *)
      let parent_id = xpath_int "rasd:Parent/text()" in
      let controller =
        match parent_id with
        | None -> None
        | Some id -> parent_controller id in

      Xml.xpathctx_set_current_context xpathctx n;
      let file_id =
        Option.default "" (xpath_string "rasd:HostResource/text()") in
      let rex = PCRE.compile "^(?:ovf:)?/disk/(.*)" in
      if PCRE.matches rex file_id then (
        (* Chase the references through to the actual file name. *)
        let file_id = PCRE.sub 1 in
        let expr = sprintf "/ovf:Envelope/ovf:DiskSection/ovf:Disk[@ovf:diskId='%s']/@ovf:fileRef" file_id in
        let file_ref =
          match xpath_string expr with
          | None -> error (f_"error parsing disk fileRef")
          | Some s -> s in
        let expr = sprintf "/ovf:Envelope/ovf:References/ovf:File[@ovf:id='%s']/@ovf:href" file_ref in
        let href =
          match xpath_string expr with
          | None -> error (f_"no href in ovf:File (id=%s)") file_ref
          | Some s -> s in

        let expr = sprintf "/ovf:Envelope/ovf:References/ovf:File[@ovf:id='%s']/@ovf:compression" file_ref in
        let compressed =
          match xpath_string expr with
          | None | Some "identity" -> false
          | Some "gzip" -> true
          | Some s -> error (f_"unsupported compression in OVF: %s") s in

        let disk = {
          source_disk = {
            s_disk_id = i;
            s_qemu_uri = "";
            s_format = Some "vmdk";
            s_controller = controller;
          };
          href = href;
          compressed = compressed
        } in
        List.push_front disk disks;
      ) else
        error (f_"could not parse disk rasd:HostResource from OVF document")
    done;
    List.rev !disks

  (* Floppies (ResourceType = 14), CDs (ResourceType = 15) and
   * CDROMs (ResourceType = 16).  (What is the difference?)  Try hard
   * to preserve the original ordering from the OVF.
   *)
  and parse_removables () =
    let removables = ref [] in
    let expr = "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=14 or rasd:ResourceType/text()=15 or rasd:ResourceType/text()=16]" in
    let obj = Xml.xpath_eval_expression xpathctx expr in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let n = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx n;
      let id =
        match xpath_int "rasd:ResourceType/text()" with
        | None -> assert false
        | Some (14|15|16 as i) -> i
        | Some _ -> assert false in

      let slot = xpath_int "rasd:AddressOnParent/text()" in

      (* Find the parent controller. *)
      let parent_id = xpath_int "rasd:Parent/text()" in
      let controller =
        match parent_id with
        | None -> None
        | Some id -> parent_controller id in

      let typ =
        match id with
        | 14 -> Floppy
        | 15 | 16 -> CDROM
        | _ -> assert false in
      let disk = {
        s_removable_type = typ;
        s_removable_controller = controller;
        s_removable_slot = slot;
      } in
      List.push_front disk removables;
    done;
    List.rev !removables

  (* Search for networks ResourceType: 10 *)
  and parse_nics () =
    let nics = ref [] in
    let expr = "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=10]" in
    let obj = Xml.xpath_eval_expression xpathctx expr in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let n = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx n;
      let vnet =
        Option.default (sprintf"eth%d" i)
                       (xpath_string "rasd:ElementName/text()") in
      let mac = xpath_string "rasd:Address/text()" in
      let nic = {
        s_mac = mac;
        s_nic_model = None;
        s_vnet = vnet;
        s_vnet_orig = vnet;
        s_vnet_type = Network;
      } in
      List.push_front nic nics
    done;
    List.rev !nics
  in

  parse_top ()
