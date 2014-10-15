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

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

class input_ova verbose ova =
  let tmpdir =
    let base_dir = (new Guestfs.guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "ova." "" in
    rmdir_on_exit t;
    t in
object
  inherit input verbose

  method as_options = "-i ova " ^ ova

  method source () =
    (* Extract ova (tar) file. *)
    let cmd = sprintf "tar -xf %s -C %s" (quote ova) (quote tmpdir) in
    if verbose then printf "%s\n%!" cmd;
    if Sys.command cmd <> 0 then
      error (f_"error unpacking OVA file: %s") cmd;

    let files = Sys.readdir tmpdir in
    let mf = ref "" in
    let ovf = ref "" in
    (* Search for the ovf file. *)
    Array.iter (fun file ->
      if Filename.check_suffix file ".ovf" then
        ovf := file
      else if Filename.check_suffix file ".mf" then
        mf := file
    ) files;

    (* verify sha1 from manifest file *)
    let mf = tmpdir // !mf in
    let rex = Str.regexp "SHA1(\\(.*\\))= \\(.*?\\)\r\\?$" in
    let lines = read_whole_file mf in
    let lines = string_nsplit "\n" lines in
    List.iter (
      fun line ->
        if Str.string_match rex line 0 then
          let file = Str.matched_group 1 line in
          let sha1 = Str.matched_group 2 line in
          let cmd = sprintf "sha1sum %s" (quote (tmpdir // file)) in
          let out = external_command ~prog cmd in
          (match out with
          | [] -> error (f_"no output from sha1sum command, see previous errors")
          | [line] ->
            let hash, _ = string_split " " line in
            if hash <> sha1 then
              error (f_"checksum of %s does not match manifest sha1 %s")
                file sha1;
          | _::_ -> error (f_"cannot parse output of sha1sum command")
          );
    ) lines;

    (* Parse the ovf file. *)
    let xml = read_whole_file (tmpdir // !ovf) in
    let doc = Xml.parse_memory xml in

    (* Handle namespaces. *)
    let xpathctx = Xml.xpath_new_context doc in
    Xml.xpath_register_ns xpathctx
      "ovf" "http://schemas.dmtf.org/ovf/envelope/1";
    Xml.xpath_register_ns xpathctx
      "rasd" "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData";
    Xml.xpath_register_ns xpathctx
      "vssd" "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData";

    let xpath_to_string expr default =
      let obj = Xml.xpath_eval_expression xpathctx expr in
      if Xml.xpathobj_nr_nodes obj < 1 then default
      else (
        let node = Xml.xpathobj_node doc obj 0 in
        Xml.node_as_string node
      )
    and xpath_to_int expr default =
      let obj = Xml.xpath_eval_expression xpathctx expr in
      if Xml.xpathobj_nr_nodes obj < 1 then default
      else (
        let node = Xml.xpathobj_node doc obj 0 in
        let str = Xml.node_as_string node in
        try int_of_string str
        with Failure "int_of_string" ->
          error (f_"expecting XML expression to return an integer (expression: %s)")
            expr
      )
    in

    (* Search for vm name. *)
    let name =
      xpath_to_string "/ovf:Envelope/ovf:VirtualSystem/ovf:Name/text()" "" in
    if name = "" then
      error (f_"could not parse ovf:Name from OVF document");

    (* Search for memory. *)
    let memory = xpath_to_int "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=4]/rasd:VirtualQuantity/text()" (1024 * 1024) in
    let memory = Int64.of_int (memory * 1024 * 1024) in

    (* Search for number of vCPUs. *)
    let vcpu = xpath_to_int "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=3]/rasd:VirtualQuantity/text()" 1 in

    (* Hard disks (ResourceType = 17). *)
    let disks = ref [] in
    let () =
      let expr = "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=17]" in
      let obj = Xml.xpath_eval_expression xpathctx expr in
      let nr_nodes = Xml.xpathobj_nr_nodes obj in
      for i = 0 to nr_nodes-1 do
        let n = Xml.xpathobj_node doc obj i in
        Xml.xpathctx_set_current_context xpathctx n;
        let address = xpath_to_int "rasd:AddressOnParent/text()" 0 in
        let parent_id = xpath_to_int "rasd:Parent/text()" 0 in
        (* Probably the parent controller. *)
        let expr = sprintf "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:InstanceId/text()=%d]/rasd:ResourceType/text()" parent_id in
        let controller = xpath_to_int expr 0 in
        (* 6: iscsi controller, 5: ide. assuming scsi or ide *)
        let target_dev =
          match controller with
          | 6 -> "sd"
          | 0 | 5 | _ (* XXX floppy should be 'fd'? *) -> "hd" in

        let target_dev = target_dev ^ drive_name address in

        Xml.xpathctx_set_current_context xpathctx n;
        let file_id = xpath_to_string "rasd:HostResource/text()" "" in
        let rex = Str.regexp "^ovf:/disk/\\(.*\\)" in
        if Str.string_match rex file_id 0 then (
          let file_id = Str.matched_group 1 file_id in
          let expr = sprintf "/ovf:Envelope/ovf:DiskSection/ovf:Disk[@ovf:diskId='%s']/@ovf:fileRef" file_id in
          let file_ref = xpath_to_string expr "" in
          if file_ref == "" then error (f_"error parsing disk fileRef");
          let expr = sprintf "/ovf:Envelope/ovf:References/ovf:File[@ovf:id='%s']/@ovf:href" file_ref in
          let file_name = xpath_to_string expr "" in
          let disk = {
            s_qemu_uri= tmpdir // file_name;
            s_format = Some "vmdk";
            s_target_dev = Some target_dev;
          } in
          disks := disk :: !disks;
        ) else
          error (f_"could not parse disk rasd:HostResource from OVF document")
      done in
    let disks = List.rev !disks in

    (* Floppies (ResourceType = 14), CDs (ResourceType = 15) and
     * CDROMs (ResourceType = 16).  (What is the difference?)  Try hard
     * to preserve the original ordering from the OVF.
     *)
    let removables = ref [] in
    let () =
      let expr =
        "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=14 or rasd:ResourceType/text()=15 or rasd:ResourceType/text()=16]" in
      let obj = Xml.xpath_eval_expression xpathctx expr in
      let nr_nodes = Xml.xpathobj_nr_nodes obj in
      for i = 0 to nr_nodes-1 do
        let n = Xml.xpathobj_node doc obj i in
        Xml.xpathctx_set_current_context xpathctx n;
        let id = xpath_to_int "rasd:ResourceType/text()" 0 in
        assert (id = 14 || id = 15 || id = 16);
        let address = xpath_to_int "rasd:AddressOnParent/text()" 0 in
        let parent_id = xpath_to_int "rasd:Parent/text()" 0 in
        (* Probably the parent controller. *)
        let expr = sprintf "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:InstanceId/text()=%d]/rasd:ResourceType/text()" parent_id in
        let controller = xpath_to_int expr 0 in
        (* 6: iscsi controller, 5: ide. assuming scsi or ide *)
        let target_dev =
          match controller with
          | 6 -> "sd"
          | 0 | 5 | _ (* XXX floppy should be 'fd'? *) -> "hd" in

        let target_dev = target_dev ^ drive_name address in

        let typ =
          match id with
            | 14 -> `Floppy
            | 15 | 16 -> `CDROM
            | _ -> assert false in
        let disk = {
          s_removable_type = typ;
          s_removable_target_dev = Some target_dev
        } in
        removables := disk :: !removables;
      done in
    let removables = List.rev !removables in

    (* Search for networks ResourceType: 10 *)
    let nics = ref [] in
    let obj = Xml.xpath_eval_expression xpathctx "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=10]"  in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let n = Xml.xpathobj_node doc obj i in
      Xml.xpathctx_set_current_context xpathctx n;
      let vnet = xpath_to_string "rasd:ElementName/text()" (sprintf"eth%d" i) in
      let nic = {
        s_mac = None;
        s_vnet = vnet;
        s_vnet_orig = vnet;
        s_vnet_type = Network;
      } in
      nics := nic :: !nics
    done;

    let source = {
      s_dom_type = "vmware";
      s_name = name;
      s_orig_name = name;
      s_memory = memory;
      s_vcpu = vcpu;
      s_features = []; (* XXX *)
      s_display = None; (* XXX *)
      s_disks = disks;
      s_removables = removables;
      s_nics = List.rev !nics;
    } in

    source
end

let input_ova = new input_ova
let () = Modules_list.register_input_module "ova"
