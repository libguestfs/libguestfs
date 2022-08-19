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

  let cmd_curl_login = sprintf "curl  -s -b cookie_file -c cookie_file -H \"Content-type: text/xml\" -d \"<requests output='XML'><request id='1' target='session'><login><username>root</username><password>%s</password></login></request></requests>\" http://localhost/doh/ > %s" passwd !tmp_output_file in
  if Sys.command cmd_curl_login <> 0 then
    error (f_"get doh session failed");
  let xml = read_whole_file !tmp_output_file in
  clean_up ();
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let status = match xpath_string "/responses/response/login/@status" with
               | None -> ""
               | Some s -> (string_trim s) in
  if status <> "ok" then
    error (f_"login failed")
;;

let do_doh_request doh_cmd =
  if verbose () then printf "Output_everrun::do_doh_request\n";
  get_doh_session ();
  let cmd_curl = sprintf "curl  -s -b cookie_file -c cookie_file -H \"Content-type: text/xml\" -d \"<requests output='XML'>%s</requests>\" http://localhost/doh/ > %s" doh_cmd !tmp_output_file in
  if verbose () then printf "%s\n" cmd_curl;
  if Sys.command cmd_curl <> 0 then
    error (f_"do doh request failed");
  let xml = read_whole_file !tmp_output_file in
  clean_up ();
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in
  let status = match xpath_string "/responses/response/@status" with
               | None -> ""
               | Some s -> (string_trim s) in
  if status <> "ok" then
    error (f_"do doh request %s failed, status is %s") cmd_curl status;
  xml
;;

let do_doh_request_ignore_response doh_cmd =
  let resp_xml = do_doh_request doh_cmd in
  let cmd = sprintf "echo %s > /dev/null" resp_xml in
  if Sys.command cmd <> 0 && verbose () then
    printf "Warning: output response to /dev/null failed\n";
;;

let trigger_doh_alert () =
  if verbose () then printf "Output_everrun::trigger_doh_alert\n";
  get_doh_session ();
  let doh_cmd = "<requests output='XML'><request id='1' target='supernova'><generate-p2v-alert /></request></requests>" in
  let cmd_curl = sprintf "curl  -s -b cookie_file -c cookie_file -H \"Content-type: text/xml\" -d \"%s\" http://localhost/doh/ > %s" doh_cmd !tmp_output_file in
  if verbose () then printf "Output_everrun::trigger_doh_alert:cmd_curl = %s\n" cmd_curl;
  if Sys.command cmd_curl <> 0 then
    error (f_"failed to trigger doh alert");
  let xml = read_whole_file !tmp_output_file in
  clean_up ();
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in
  let status = match xpath_string "/responses/response/@status" with
               | None -> ""
               | Some s -> (string_trim s) in
  if status <> "ok" then
    error (f_"Everrun Doh command failed status was: %s") status;
;;

let get_primary_host_oid () =
  if verbose () then printf "Output_everrun::get_primary_host_oid\n";
  let cmd_curl_topology = "<request id='1' target='host'><select></select></request>" in
  let curl_resp_xml = do_doh_request cmd_curl_topology in
  let curl_resp_doc = Xml.parse_memory curl_resp_xml in
  let xpathctx = Xml.xpath_new_context curl_resp_doc in
  let xpath_string = xpath_string xpathctx in
  let xpath_bool = xpath_bool xpathctx in

  let primary_host_id = ref "" in
  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/host" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no host in the everrun system");
  for i = 0 to nr_nodes-1 do
    let node = Xml.xpathobj_node obj i in
    Xml.xpathctx_set_current_context xpathctx node;
    if xpath_bool "is-primary" then (
      let id = match xpath_string "@id" with
               | None -> ""
               | Some id -> (string_trim id) in
      primary_host_id := id;
    )
  done;
  !primary_host_id
;;

let get_storage_group_oid doc os =
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

      if storage_group_name_temp == os then (
        storage_group_name := storage_group_name_temp;
        let id = match xpath_string "@id" with
                            | None -> ""
                            | Some fid -> (string_trim fid) in
        storage_group_id := id;
        found_sg := true;
      )
    )
  done;
  if !storage_group_name <> os then
    error (f_"there is no storage group match name in the everrun system");
  !storage_group_id;
;;

let get_network_oid doc network_name =
    let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  let network_id = ref "" in
  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/sharednetwork" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no shared network in the everrun system");
  let found_nw = ref false in
  for i = 0 to nr_nodes-1 do
    if not !found_nw then (
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;
      let network_name_tmp = match xpath_string "name" with
                             | None -> ""
                             | Some netname -> (string_trim netname)
      in
      if network_name_tmp == network_name then (
      let id = match xpath_string "@id" with
               | None -> ""
               | Some nid -> (string_trim nid) in
      network_id := id;
        found_nw := true;
      )
    )
  done;
  if !network_id == "" then
    error (f_"there is no shared network match name in the everrun system");
  !network_id;
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

        if domain_name == host_name then
          error (f_"a domain with the same name has already exist in the system");
    done;
;;

let get_default_storage_group doc =
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in
  let xpath_bool = xpath_bool xpathctx in

  let storage_group_id = ref "" in
  let storage_group_name = ref "" in
  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/storagegroup" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no storage group in the everrun system");

  let found_sg = ref false in
  for i = 0 to nr_nodes-1 do
    if not !found_sg then (
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;
      if xpath_bool "is-default" then (
        let storage_group_name_temp = match xpath_string "name" with
                                      | None -> ""
                                      | Some sname -> (string_trim sname) in
        let id = match xpath_string "@id" with
                 | None -> ""
                 | Some fid -> (string_trim fid) in
        storage_group_name := storage_group_name_temp;

        storage_group_id := id;
        found_sg := true;
      )
    )
  done;
  if !storage_group_id == "" || !storage_group_name == "" then
    error (f_"failed to get the default storage group");
  ({
    s_storage_group_id = !storage_group_id;
    s_storage_group_name = !storage_group_name;
  })
;;

let get_default_virtual_network doc =
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in
  let xpath_bool = xpath_bool xpathctx in

  let virtual_network_id = ref "" in
  let virtual_network_name = ref "" in
  let obj = Xml.xpath_eval_expression xpathctx
    "/responses/response/output/sharednetwork" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no shared network in the everrun system");
  let found_nw = ref false in
  for i = 0 to nr_nodes-1 do
    if not !found_nw then (
      let node = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx node;
      if xpath_bool "withPortal" then (
        let network_name_tmp = match xpath_string "name" with
                               | None -> ""
                               | Some netname -> (string_trim netname) in
        let id = match xpath_string "@id" with
                 | None -> ""
                 | Some nid -> (string_trim nid) in
        virtual_network_id := id;
        virtual_network_name := network_name_tmp;
        found_nw := true;
      )
    )
  done;
  if !virtual_network_id == "" || !virtual_network_name == "" then
    error (f_"failed to get the default virtual network");
  ({
    v_network_id = !virtual_network_id;
    v_network_name = !virtual_network_name;
  })
;;

let parse_config_without_cfg_file source targets =
  if verbose () then printf "Output_everrun::parse_config_without_cfg_file\n";
  (* Get watch response *)
  let cmd_curl_watch = "<request id='1' target='supernova'><watch/></request>" in
  let everrun_response_xml = do_doh_request cmd_curl_watch in
  let everrun_response_doc = Xml.parse_memory everrun_response_xml in

  (* Get all shared networks *)
  let cmd_curl_topology = "<request id='1' target='sharednetwork'><select>sharednetwork</select></request>" in
  let everrun_network_response_xml = do_doh_request cmd_curl_topology in
  let everrun_network_response_doc = Xml.parse_memory everrun_network_response_xml in

  check_domain_existence everrun_response_doc source.s_name;

  let default_storage_group = get_default_storage_group everrun_response_doc in
  let default_virtual_network = get_default_virtual_network everrun_network_response_doc in
  let disks = ref [] in
  let networks = ref [] in
  List.iter (
    fun t ->
      let add_disk name =
        disks := {
          c_disk_name = name;
          c_storage_group_name = default_storage_group.s_storage_group_name;
          c_storage_group_id = default_storage_group.s_storage_group_id;
        } :: !disks in
      let name = t.target_overlay.ov_sd in
      add_disk name;
  ) targets;

  List.iter (
    fun nic ->
    let add_network name =
      networks := {
        c_network_name = name;
        c_virtual_network_name = default_virtual_network.v_network_name;
        c_virtal_network_id = default_virtual_network.v_network_id;
      } :: !networks in
      let name = nic.s_vnet in
      add_network name;
  ) source.s_nics;
  ({
    c_domain_name = source.s_name;
    c_disks = !disks;
    c_networks = !networks;
  })
;;

let parse_config_file os domain_name =
  if verbose () then printf "Output_everrun::parse_config_file\n";
  (* Get watch response *)
  let cmd_curl_watch = "<request id='1' target='supernova'><watch/></request>" in
  let everrun_response_xml = do_doh_request cmd_curl_watch in
  let everrun_response_doc = Xml.parse_memory everrun_response_xml in

  (* Get all shared networks *)
  let cmd_curl_topology = "<request id='1' target='sharednetwork'><select>sharednetwork</select></request>" in
  let everrun_network_response_xml = do_doh_request cmd_curl_topology in
  let everrun_network_response_doc = Xml.parse_memory everrun_network_response_xml in

  let xml = read_whole_file os in
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  let xpath_string = xpath_string xpathctx in

  check_domain_existence everrun_response_doc domain_name;

  let obj = Xml.xpath_eval_expression xpathctx
    "/configs/devices/disk" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no disk defined in the config file");
  let disks = ref [] in
  let networks = ref [] in
  for i = 0 to nr_nodes-1 do
    let node = Xml.xpathobj_node obj i in
    Xml.xpathctx_set_current_context xpathctx node;
    let add_disk name storage_group_name storage_group_id =
      disks := {
        c_disk_name = name;
        c_storage_group_name = storage_group_name;
        c_storage_group_id = storage_group_id;
      } :: !disks in
    let name = match xpath_string "target/@dev" with
               | None -> ""
               | Some d_name -> (string_trim d_name) in
    let storage_group_name = match xpath_string "source/storage-group/@name" with
                             | None -> ""
                             | Some sg_name -> (string_trim sg_name) in
    let storage_group_id = get_storage_group_oid everrun_response_doc storage_group_name in
    add_disk name storage_group_name storage_group_id;
  done;
  let obj = Xml.xpath_eval_expression xpathctx
    "/configs/devices/interface" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
      error (f_"there is no interface defined in the config file");
  for i = 0 to nr_nodes-1 do
    let node = Xml.xpathobj_node obj i in
    Xml.xpathctx_set_current_context xpathctx node;
    let add_network name virtual_network_name virtal_network_id =
      networks := {
        c_network_name = name;
        c_virtual_network_name = virtual_network_name;
        c_virtal_network_id = virtal_network_id;
      } :: !networks in
    let name = match xpath_string "target/@dev" with
               | None -> ""
               | Some d_name -> (string_trim d_name) in
    let virtual_network_name = match xpath_string "source/@network" with
                               | None -> ""
                               | Some net_name -> (string_trim net_name) in
    let virtal_network_id = get_network_oid everrun_network_response_doc virtual_network_name in
    add_network name virtual_network_name virtal_network_id;
  done;
  ({
    c_domain_name = domain_name;
    c_disks = !disks;
    c_networks = !networks;
  })
;;

let create_volumes config =
  if verbose () then printf "Output_everrun::create_volumes\n";
  let volumes = ref [] in
  let primary_host_oid = get_primary_host_oid () in
  List.iter (
    fun disk ->
      let add_volume vol_path vol_id vol_name disk_name =
        volumes := {
          e_vol_path = vol_path;
          e_vol_id = vol_id;
          e_vol_name = vol_name;
          e_disk_name = disk_name;
        } :: !volumes in
      let storage_group_id = get_everrun_obj_id disk.c_storage_group_id in
      let newsize = 0L in
      let vol_name = get_CDATA config.c_domain_name ^ disk.c_disk_name in
      let cmd_curl_create_vol = sprintf "<request id='1' target='volume'><create ><volume from='%s'><size>%Ld</size><container-size>%Ld</container-size><hard>true</hard><name>%s</name><image-type>RAW</image-type><description>p2v created disk</description></volume></create></request>"
                                        storage_group_id newsize newsize vol_name in
      let curl_resp_xml = do_doh_request cmd_curl_create_vol in
      let curl_resp_doc = Xml.parse_memory curl_resp_xml in
      let xpathctx = Xml.xpath_new_context curl_resp_doc in
      let xpath_string = xpath_string xpathctx in

      let vol_id = match xpath_string "/responses/response/created/@id" with
                   | None -> ""
                   | Some id -> (string_trim id) in
      let vol_path = match xpath_string "/responses/response/created/@path" with
                   | None -> ""
                   | Some path -> (string_trim path) in
      let cmd_curl_set_primary_vol = sprintf "<request id='1' target='%s'><set-volume-orig-mirror-copy-src><node>%s</node></set-volume-orig-mirror-copy-src></request>"
                                             vol_id primary_host_oid in
      do_doh_request_ignore_response cmd_curl_set_primary_vol;

      let cmd_qemu_img = sprintf "qemu-img info %s" vol_path in
      if Sys.command cmd_qemu_img <> 0 then
        error (f_"execute command qemu-img info %s failed") vol_path;
      add_volume vol_path vol_id vol_path disk.c_disk_name;
  ) config.c_disks;

  !volumes;
;;

let generate_networks_xml config =
  let networks = ref "<networks>" in
  List.iter (
    fun net ->
      let network_node = sprintf "<network ref=\'%s\'/>" net.c_virtal_network_id in
      networks := !networks ^ network_node;
  ) config.c_networks;
  networks := !networks ^ "</networks>";
  !networks;
;;

let generate_volumes_xml everrun_volumes =
  let volumes = ref "<volumes>" in
  List.iter (
    fun vol ->
      let volume_node = sprintf "<volume ref='%s'/>" vol.e_vol_id in
      volumes := !volumes ^ volume_node;
  ) everrun_volumes;
  volumes := !volumes ^ "</volumes>";
  !volumes;
;;

let create_guest domain_name vcpus memsize availability config everrun_volumes =
  if verbose () then printf "Output_everrun::create_guest\n";
  let domain_name = get_CDATA domain_name in
  let vcpus = vcpus in
  let memsize = memsize in
  let description = get_CDATA "p2v created vm" in
  let availability = availability in
  let cmd_curl_create_guest = sprintf "<request id='1' target='vm'><create-dynamic><name>%s</name><description>%s</description><virtual-cpus>%d</virtual-cpus><memory>%Ld</memory><availability-level>%s</availability-level><virtualization>hvm</virtualization><autostart>false</autostart>"
                                      domain_name description vcpus memsize availability in
  let disk_xml = generate_volumes_xml everrun_volumes in
  let network_xml = generate_networks_xml config in
  let cmd_curl_create_guest = cmd_curl_create_guest ^ disk_xml ^ network_xml ^ "</create-dynamic></request>" in
  do_doh_request_ignore_response cmd_curl_create_guest;
;;

let get_vol_path_for_disk_name volumes disk_name =
  let vol_path = ref "" in
  List.iter (
    fun volume ->
      if volume.e_disk_name == disk_name then
        vol_path := volume.e_vol_path;
  ) volumes;
  if !vol_path == "" then
    error (f_"volume path not found for disk name %s") disk_name;
  !vol_path;
;;

class output_everrun os availability = object
  inherit output
  val mutable everrun_config = None
  val mutable everrun_volumes = None
  val mutable use_config = false

  method as_options = (
    match availability with
    | "FT" -> sprintf "-o everrunft -os %s" os
    | "HA" -> sprintf "-o everrunha -os %s" os
    | s ->
      error (f_"unknown -os option: %s") s
  )

  method set_use_config use_cfg =
    use_config <- use_cfg;

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    if verbose () then (
      printf "Output_everrun::prepare_targets:source=>%s\n" (string_of_source source);
      printf "Output_everrun::prepare_targets:targets=>\n";
      List.iter (
        fun target ->
          printf "%s\n" (string_of_target target);
      ) targets;
    );
    let config = match use_config with
                 | true -> parse_config_file os source.s_name
                 | false -> parse_config_without_cfg_file source targets
    in
    let volumes = create_volumes config in
    everrun_config <- Some config;
    everrun_volumes <- Some volumes;

    List.map (
      fun t ->
        let target_file = get_vol_path_for_disk_name volumes t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets;

  method create_metadata source _ target_buses guestcaps _ target_firmware =

    let domain_name = source.s_name in
    let vcpus = source.s_vcpu in
    let memory_mb = source.s_memory /^ 1024L /^ 1024L in

    let config = match everrun_config with
                 | None -> assert false
                 | Some config -> config in

    let volumes = match everrun_volumes with
                  | None -> assert false
                  | Some vols -> vols in

    create_guest domain_name vcpus memory_mb availability config volumes;

end

let output_everrun = new output_everrun
let () = Modules_list.register_output_module "everrunft"
let () = Modules_list.register_output_module "everrunha"
