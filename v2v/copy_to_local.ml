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

(* The separate virt-v2v-copy-to-local tool. *)

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext
open Getopt.OptionName

open Utils
open Xpath_helpers

type source_t = Xen_ssh of string | ESXi of string | Test

let rec main () =
  let input_conn = ref None in
  let password_file = ref None in

  let set_string_option_once optname optref arg =
    match !optref with
    | Some _ ->
       error (f_"%s option used more than once on the command line") optname
    | None ->
       optref := Some arg
  in

  (* Handle the command line. *)
  let argspec = [
    [ M"ic" ],       Getopt.String ("uri", set_string_option_once "-ic" input_conn),
                                            s_"Libvirt URI";
    [ M"ip" ],       Getopt.String ("file", set_string_option_once "-ip" password_file),
                                            s_"Use password from file";
    [ L"password-file" ], Getopt.String ("file", set_string_option_once "--password-file" password_file),
                                            s_"Use password from file";
  ] in
  let args = ref [] in
  let anon_fun s = List.push_front s args in
  let usage_msg =
    sprintf (f_"\
%s: copy a remote guest to the local machine

Copy the remote guest:

  virt-v2v-copy-to-local -ic xen+ssh://root@xen.example.com guest

  virt-v2v-copy-to-local -ic esx://esxi.example.com guest

Then perform the conversion step:

  virt-v2v -i libvirtxml guest.xml -o local -os /var/tmp

To clean up:

  rm guest.xml guest-disk*

A short summary of the options is given below.  For detailed help please
read the man page virt-v2v-copy-to-local(1).
")
      prog in
  let opthandle = create_standard_options argspec ~anon_fun usage_msg in
  Getopt.parse opthandle;

  let args = !args in
  let input_conn = !input_conn in
  let password_file = !password_file in

  let input_conn =
    match input_conn with
    | None ->
       error (f_"the -ic parameter is required") (* at the moment *)
    | Some ic -> ic in

  (* Check this is a libvirt URI we can understand. *)
  let parsed_uri =
    try Xml.parse_uri input_conn
    with Invalid_argument msg ->
      error (f_"could not parse '-ic %s'.  Original error message was: %s")
            input_conn msg in
  let source =
    match parsed_uri.Xml.uri_server, parsed_uri.Xml.uri_scheme with
    | Some server, Some "xen+ssh" -> (* Xen over SSH *)
       Xen_ssh server
    | Some server, Some "esx" -> (* esxi over https *)
       ESXi server

    (* This is just for testing, and is not documented. *)
    | None, Some "test" ->
       Test

    (* We can probably extend this list in future. *)
    | _ ->
       error (f_"only copies from VMware ESXi or Xen over SSH are supported.  See the virt-v2v-copy-to-local(1) manual page.") in

  (* We expect a single extra argument, which is the guest name. *)
  let guest_name =
    match args with
    | [] ->
       error (f_"missing guest name.  See the virt-v2v-copy-to-local(1) manual page.")
    | [arg] -> arg
    | _ ->
       error (f_"too many command line parameters.  See the virt-v2v-copy-to-local(1) manual page.") in

  (* Print the version, easier than asking users to tell us. *)
  debug "%s: %s %s (%s)"
        prog Guestfs_config.package_name
        Guestfs_config.package_version Guestfs_config.host_cpu;

  (* Get the remote libvirt XML. *)
  message (f_"Fetching the remote libvirt XML metadata ...");
  let xml = Libvirt_utils.dumpxml ?password_file ~conn:input_conn guest_name in

  debug "libvirt XML from remote server:\n%s" xml;

  (* Get the disk remote paths from the XML. *)
  message (f_"Parsing the remote libvirt XML metadata ...");
  let disks, dcpath, xml = parse_libvirt_xml guest_name xml in

  debug "libvirt XML after modifying for local disks:\n%s" xml;

  (* For VMware ESXi source, we have to massage the disk path. *)
  let disks =
    match source with
    | ESXi server ->
       let dcpath =
         match dcpath with
         | Some dcpath -> dcpath
         | None ->
            error (f_"vcenter: <vmware:datacenterpath> was not found in the XML.  You need to upgrade to libvirt ≥ 1.2.20.") in
       List.map (
         fun (remote_disk, local_disk) ->
           let { VCenter.https_url; sslverify; session_cookie } =
             VCenter.map_source dcpath parsed_uri server remote_disk in
           debug "esxi: source disk %s (sslverify=%b)" https_url sslverify;
           (https_url, local_disk, sslverify, session_cookie)
       ) disks
    | Test | Xen_ssh _ ->
       List.map (fun (remote_disk, local_disk) ->
                 (remote_disk, local_disk, false, None)) disks in

  (* Delete the disks on exit, unless we finish everything OK. *)
  let delete_on_exit = ref true in
  at_exit (
    fun () ->
      if !delete_on_exit then (
        List.iter (
          fun (_, local_disk, _, _) ->
            try Unix.unlink local_disk with _ -> ()
        ) disks
      )
    );

  (* Copy the disks. *)
  let n = List.length disks in
  List.iteri (
    fun i (remote_disk, local_disk, sslverify, cookie) ->
    message (f_"Copying remote disk %d/%d to %s")
            (i+1) n local_disk;

    (* How we copy it depends on the source. *)
    match source with
    | Xen_ssh server ->
       let { Xml.uri_user = user; uri_port = port } = parsed_uri in

       let cmd =
         sprintf "set -o pipefail; ssh%s %s%s dd bs=1M if=%s | dd%s conv=sparse bs=1M of=%s"
                 (match port with
                  | n when n >= 1 -> sprintf " -p %d" n
                  | _ -> "")
                 (match user with
                  | None -> ""
                  | Some u -> sprintf "%s@" (quote u))
                 server
                 (quote remote_disk)
                 (if quiet () then ""
                  else " status=progress")
                 (quote local_disk) in
       if shell_command cmd <> 0 then
         error (f_"ssh copy command failed, see earlier errors");

    | ESXi _ ->
       let curl_args = ref [
         "url", Some remote_disk;
         "output", Some local_disk;
       ] in
       if not sslverify then List.push_back curl_args ("insecure", None);
       (match cookie with
        | None -> ()
        | Some cookie -> List.push_back curl_args ("cookie", Some cookie)
       );
       if quiet () then List.push_back curl_args ("silent", None);

       let curl_h = Curl.create !curl_args in
       if verbose () then
         Curl.print stderr curl_h;
       ignore (Curl.run curl_h)

    | Test ->
       let cmd = [ "cp"; remote_disk; local_disk ] in
       if run_command cmd <> 0 then
         error (f_"copy command failed, see earlier errors");
  ) disks;

  let guest_xml = guest_name ^ ".xml" in
  message (f_"Writing libvirt XML metadata to %s ...") guest_xml;
  with_open_out guest_xml (fun chan -> output_string chan xml);

  (* Finished, so don't delete the disks on exit. *)
  message (f_"Finishing off");
  delete_on_exit := false

(* This is a greatly simplified version of the parsing function
 * in virt-v2v parse_libvirt_xml.ml:parse_libvirt_xml
 * It also modifies the XML <disk> elements to point to local disks.
 *)
and parse_libvirt_xml guest_name xml =
  (* Parse the XML. *)
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in
  Xml.xpath_register_ns xpathctx
                        "vmware" "http://libvirt.org/schemas/domain/vmware/1.0";
  let xpath_string = xpath_string xpathctx in

  (* Get the dcpath, present in libvirt >= 1.2.20. *)
  let dcpath = xpath_string "/domain/vmware:datacenterpath" in

  (* Parse the disks. *)
  let get_disks, add_disk =
    let disks = ref [] and i = ref 0 in
    let get_disks () = List.rev !disks in
    let add_disk remote_disk =
      (* Generate a unique name for each output disk. *)
      incr i;
      let local_disk = sprintf "%s-disk%d" guest_name !i in

      List.push_front (remote_disk, local_disk) disks;
      local_disk
    in
    get_disks, add_disk
  in

  (* node is a <disk> node, containing a <source> element.  Update the
   * node to point to a local file.
   *)
  let update_disk_node node local_disk =
    Xml.set_prop node "type" "file";
    let obj = Xml.xpath_eval_expression xpathctx "source" in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    assert (nr_nodes >= 1);
    for i = 0 to nr_nodes-1 do
      let source_node = Xml.xpathobj_node obj i in
      ignore (Xml.unset_prop source_node "dev");
      Xml.set_prop source_node "file" local_disk
    done
  in

  let obj =
    Xml.xpath_eval_expression xpathctx
                              "/domain/devices/disk[@device='disk']" in
  let nr_nodes = Xml.xpathobj_nr_nodes obj in
  if nr_nodes < 1 then
    error (f_"this guest has no non-removable disks");

  for i = 0 to nr_nodes-1 do
    let node = Xml.xpathobj_node obj i in
    Xml.xpathctx_set_current_context xpathctx node;

    (* The <disk type='...'> attribute may be 'block' or 'file'.
     * We ignore any other types.
     *)
    match xpath_string "@type" with
    | None ->
       warning (f_"<disk> element with no type attribute ignored")

    | Some "block" ->
       (match xpath_string "source/@dev" with
        | Some path ->
           let local_disk = add_disk path in
           update_disk_node node local_disk
        | None -> ()
       );
    | Some "file" ->
       (match xpath_string "source/@file" with
        | Some path ->
           let local_disk = add_disk path in
           update_disk_node node local_disk
        | None -> ()
       );

    | Some disk_type ->
       warning (f_"<disk type='%s'> was ignored") disk_type
  done;

  let xml = Xml.to_string doc ~format:true in
  get_disks (), dcpath, xml

let () = run_main_and_handle_errors main
