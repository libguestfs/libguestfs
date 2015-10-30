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

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

let tmp_output_file = ref "tmp_output.out"

let clean_up () =
  let cmd = sprintf "rm -rf %s" !tmp_output_file in
  if Sys.command cmd <> 0 then
    error (f_"delete temp response file error");
;;

let get_doh_session () =
  let passwd = match get_everrun_passwd () with
               | "" -> error (f_"No password is found");
               | s -> s in

  let cmd_curl_login = sprintf "curl -s -b cookie_file -c cookie_file -H \"Content-type: text/xml\" -d \"<requests output='XML'><request id='1' target='session'><login><username>root</username><password>%s</password></login></request></requests>\" http://localhost/doh/ > %s" passwd !tmp_output_file in
  if Sys.command cmd_curl_login <> 0 then
    error (f_"get doh session failed");
  let xml = read_whole_file !tmp_output_file in
  clean_up ();
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let status = match xpath_string "/responses/response/login/@status" with
               | None -> ""
               | Some s -> s in
  if status <> "ok" then
    error (f_"login failed")
;;

let do_doh_request doh_cmd =
  if verbose () then printf "Output_everrun: do_doh_request";
  get_doh_session ();
  let cmd_curl = sprintf "curl  -s -b cookie_file -c cookie_file -H \"Content-type: text/xml\" -d \"<requests output='XML'>%s</requests>\" http://localhost/doh/ > %s" doh_cmd !tmp_output_file in
  if verbose () then printf "Output_everrun: do_doh_request: cmd_curl = %s" cmd_curl;
  if Sys.command cmd_curl <> 0 then
    error (f_"do doh request failed");
  let xml = read_whole_file !tmp_output_file in
  clean_up ();
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in
  let status = match xpath_string "/responses/response/@status" with
               | None -> ""
               | Some s -> s in
  if status <> "ok" then
    error (f_"login failed");
  doc
;;

let get_storage_group_id doc os =
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let storage_group_id = ref "" in
  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/storagegroup" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no storage group in the everrun system");
  let storage_group_name = ref "" in
  let found_sg = ref false in
  for i = 0 to nr_nodes-1 do
    if not !found_sg then (
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;
      let storage_group_name_temp =
        match xpath_string "name" with
        | None -> ""
        | Some sname -> (string_trim sname)
      in

      if storage_group_name_temp = os then (
        storage_group_name := storage_group_name_temp;
        let full_id = match xpath_string "@id" with
                      | None -> ""
                      | Some fid -> (string_trim fid) in
        storage_group_id := get_everrun_obj_id full_id;
        found_sg := true;
      )
    )
  done;
  if !storage_group_name <> os then
    error (f_"there is no storage group match name in the everrun system");
  !storage_group_id;
;;

let check_domain_existence doc host_name =
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/localvirtualmachine" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes > 0 then
    for i = 0 to nr_nodes-1 do
        let node = Xml.xpathobj_node obj i in
        Xml.xpathctx_set_current_context xpathctx node;
        let domain_name =
          match xpath_string "name" with
          | None -> ""
          | Some sname -> (string_trim sname)
        in

        if domain_name = host_name then
          error (f_"a domain with the same name has already exist in the system");
    done;
;;

let parse_config_file os =

  let cmd = sprintf "curl http://localhost:8999 > %s" !tmp_output_file in
  if Sys.command cmd <> 0 then
    error (f_"get response error");

  let xml = read_whole_file !tmp_output_file in
  let everrun_response_doc = Xml.parse_memory xml in
  clean_up ();

  let xml = read_whole_file os in
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let domain_name = match xpath_string "/configs/@domain_name" with
                    | None -> ""
                    | Some d_name -> (string_trim d_name) in
  check_domain_existence everrun_response_doc domain_name;

  let obj = Xml.xpath_eval_expression xpathctx
    "/configs/device" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no device defined in the config file");
  let disks = ref [] in
  let networks = ref [] in
  for i = 0 to nr_nodes-1 do
    let node = Xml.xpathobj_node obj i in
    Xml.xpathctx_set_current_context xpathctx node;
    let device_type = match xpath_string "type" with
                      | None -> ""
                      | Some d_type -> (string_trim d_type) in
    if device_type = "disk" then (
      let add_disk name storage_group_name storage_group_id =
        disks := {
          c_disk_name = name;
          c_storage_group_name = storage_group_name;
          c_storage_group_id = storage_group_id;
        } :: !disks in
      let name = match xpath_string "name" with
                 | None -> ""
                 | Some d_name -> (string_trim d_name) in
      let storage_group_name = match xpath_string "storage-group-name" with
                               | None -> ""
                               | Some sg_name -> (string_trim sg_name) in
      let storage_group_id = get_storage_group_id everrun_response_doc storage_group_name in
      add_disk name storage_group_name storage_group_id;
    )
    else if device_type = "network" then (
      let add_network name virtual_network_name virtal_network_id =
        networks := {
          c_network_name = name;
          c_virtual_network_name = virtual_network_name;
          c_virtal_network_id = virtal_network_id;
        } :: !networks in
        let name = match xpath_string "name" with
                   | None -> ""
                   | Some d_name -> (string_trim d_name) in
        let virtual_network_name = match xpath_string "virtual-network-name" with
                                  | None -> ""
                                  | Some net_name -> (string_trim net_name) in
        let virtal_network_id = "" in
        add_network name virtual_network_name virtal_network_id;
    )
    else error (f_"unknown device type");
  done;
  ({
    c_domain_name = domain_name;
    c_disks = !disks;
    c_networks = !networks;
  })
;;

let print_disks disks =
  List.iter (
    fun disk ->
      let temp = sprintf "{ name: %s, storage_group_name: %s, storage_group_id: %s }\n"
      disk.c_disk_name disk.c_storage_group_name disk.c_storage_group_id in
      printf "%s\n" temp;
  ) disks;
;;

let print_networks networks =
    List.iter (
    fun network ->
      let temp = sprintf "{ name: %s, virtual_network_name: %s, virtal_network_id: %s }\n"
      network.c_network_name network.c_virtual_network_name network.c_virtal_network_id in
      printf "%s\n" temp;
  ) networks;
;;

class output_everrun os availability = object
  inherit output

  val mutable capabilities_doc = None

  method as_options = (
    printf "[franklin] as options ok\n";
    let config = parse_config_file os in
    printf "[franklin] domain_name = %s\n" config.c_domain_name;
    print_disks config.c_disks;
    print_networks config.c_networks;
    match availability with
    | "FT" -> sprintf "-o everrunft -os %s" os
    | "HA" -> sprintf "-o everrunha -os %s" os
    | s ->
      error (f_"unknown -os option: %s") s
  )

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    (* capabilities_doc <- Some doc; *)
 (*    let cmd = sprintf "curl http://localhost:8999 > /home/franklin/temp/response.xml" in
    if Sys.command cmd <> 0 then
      error (f_"get response error"); *)
    List.map (
      fun t ->
        let target_file = source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method create_metadata source _ target_buses guestcaps _ target_firmware =
    printf "[franklin] create_metadata ok";
    (* We don't know what target features the hypervisor supports, but
     * assume a common set that libvirt supports.
     *)
    let target_features =
      match guestcaps.gcaps_arch with
      | "i686" -> [ "acpi"; "apic"; "pae" ]
      | "x86_64" -> [ "acpi"; "apic" ]
      | _ -> [] in

    let doc =
      Output_libvirt.create_libvirt_xml source target_buses
        guestcaps target_features target_firmware in

    let name = source.s_name in
    let file = os // name ^ ".xml" in

    let chan = open_out file in
    DOM.doc_to_chan chan doc;
    close_out chan

end

let output_everrun = new output_everrun
let () = Modules_list.register_output_module "everrunft"
let () = Modules_list.register_output_module "everrunha"
