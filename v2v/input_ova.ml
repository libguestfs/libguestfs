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
    (* Extract ova file. *)
    let exploded =
      (* The spec allows a directory to be specified as an ova.  This
       * is also pretty convenient.
       *)
      if is_directory ova then ova
      else (
        let uncompress_head zcat file =
          let cmd = sprintf "%s %s" zcat (quote file) in
          let chan_out, chan_in, chan_err = Unix.open_process_full cmd [||] in
          let buf = String.create 512 in
          let len = input chan_out buf 0 (String.length buf) in
          (* We're expecting the subprocess to fail because we close
           * the pipe early, so:
           *)
          ignore (Unix.close_process_full (chan_out, chan_in, chan_err));

          let tmpfile, chan = Filename.open_temp_file ~temp_dir:tmpdir "ova.file." "" in
          output chan buf 0 len;
          close_out chan;

          tmpfile in

        let untar ?(format = "") file outdir =
          let cmd = sprintf "tar -x%sf %s -C %s" format (quote file) (quote outdir) in
          if verbose then printf "%s\n%!" cmd;
          if Sys.command cmd <> 0 then
            error (f_"error unpacking %s, see earlier error messages") ova in

        match detect_file_type ova with
        | `Tar ->
          (* Normal ovas are tar file (not compressed). *)
          untar ova tmpdir;
          tmpdir
        | `Zip ->
          (* However, although not permitted by the spec, people ship
           * zip files as ova too.
           *)
          let cmd = sprintf "unzip%s -j -d %s %s"
            (if verbose then "" else " -q")
            (quote tmpdir) (quote ova) in
          if verbose then printf "%s\n%!" cmd;
          if Sys.command cmd <> 0 then
            error (f_"error unpacking %s, see earlier error messages") ova;
          tmpdir
        | (`GZip|`XZ) as format ->
          let zcat, tar_fmt =
            match format with
            | `GZip -> "zcat", "z"
            | `XZ -> "xzcat", "J"
            | _ -> assert false in
          let tmpfile = uncompress_head zcat ova in
          let tmpfiletype = detect_file_type tmpfile in
          (* Remove tmpfile from tmpdir, to leave it empty. *)
          Sys.remove tmpfile;
          (match tmpfiletype with
          | `Tar ->
            untar ~format:tar_fmt ova tmpdir;
            tmpdir
          | `Zip | `GZip | `XZ | `Unknown ->
            error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
          )
        | `Unknown ->
          error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
      ) in

    (* Exploded path must be absolute (RHBZ#1155121). *)
    let exploded =
      if not (Filename.is_relative exploded) then exploded
      else Sys.getcwd () // exploded in

    (* Find files in [dir] ending with [ext]. *)
    let find_files dir ext =
      let rec loop = function
        | [] -> []
        | dir :: rest ->
          let files = Array.to_list (Sys.readdir dir) in
          let files = List.map (Filename.concat dir) files in
          let dirs, files = List.partition Sys.is_directory files in
          let files = List.filter (
            fun x ->
              Filename.check_suffix x ext
          ) files in
          files @ loop (rest @ dirs)
      in
      loop [dir]
    in

    (* Search for the ovf file. *)
    let ovf = find_files exploded ".ovf" in
    let ovf =
      match ovf with
      | [] ->
        error (f_"no .ovf file was found in %s") ova
      | [x] -> x
      | _ :: _ ->
        error (f_"more than one .ovf file was found in %s") ova in

    (* Read any .mf (manifest) files and verify sha1. *)
    let mf = find_files exploded ".mf" in
    let rex = Str.regexp "SHA1(\\(.*\\))=\\([0-9a-fA-F]+\\)\r?" in
    List.iter (
      fun mf ->
        let chan = open_in mf in
        let rec loop () =
          let line = input_line chan in
          if Str.string_match rex line 0 then (
            let disk = Str.matched_group 1 line in
            let expected = Str.matched_group 2 line in
            let cmd = sprintf "sha1sum %s" (quote (exploded // disk)) in
            let out = external_command ~prog cmd in
            match out with
            | [] ->
              error (f_"no output from sha1sum command, see previous errors")
            | [line] ->
              let actual, _ = string_split " " line in
              if actual <> expected then
                error (f_"checksum of disk %s does not match manifest %s (actual sha1(%s) = %s, expected sha1 (%s) = %s)")
                  disk mf disk actual disk expected;
              if verbose then
                printf "sha1 of %s matches expected checksum %s\n%!"
                  disk expected
            | _::_ -> error (f_"cannot parse output of sha1sum command")
          )
        in
        (try loop () with End_of_file -> ());
        close_in chan
    ) mf;

    (* Parse the ovf file. *)
    let xml = read_whole_file ovf in
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

    (* Helper function to return the parent controller of a disk. *)
    let parent_controller id =
      let expr = sprintf "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:InstanceID/text()=%d]/rasd:ResourceType/text()" id in
      let controller = xpath_to_int expr 0 in

      (* 6: iscsi controller, 5: ide *)
      match controller with
      | 6 -> Some Source_SCSI
      | 5 -> Some Source_IDE
      | 0 ->
        warning ~prog (f_"ova disk has no parent controller, please report this as a bug supplying the *.ovf file extracted from the ova");
        None
      | _ ->
        warning ~prog (f_"ova disk has an unknown VMware controller type (%d), please report this as a bug supplying the *.ovf file extracted from the ova")
          controller;
        None
    in

    (* Hard disks (ResourceType = 17). *)
    let disks = ref [] in
    let () =
      let expr = "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=17]" in
      let obj = Xml.xpath_eval_expression xpathctx expr in
      let nr_nodes = Xml.xpathobj_nr_nodes obj in
      for i = 0 to nr_nodes-1 do
        let n = Xml.xpathobj_node doc obj i in
        Xml.xpathctx_set_current_context xpathctx n;

        (* XXX We assume the OVF lists these in order.
        let address = xpath_to_int "rasd:AddressOnParent/text()" 0 in
        *)

        (* Find the parent controller. *)
        let parent_id = xpath_to_int "rasd:Parent/text()" 0 in
        let controller =
          match parent_id with
          | 0 -> None
          | id -> parent_controller id in

        Xml.xpathctx_set_current_context xpathctx n;
        let file_id = xpath_to_string "rasd:HostResource/text()" "" in
        let rex = Str.regexp "^ovf:/disk/\\(.*\\)" in
        if Str.string_match rex file_id 0 then (
          (* Chase the references through to the actual file name. *)
          let file_id = Str.matched_group 1 file_id in
          let expr = sprintf "/ovf:Envelope/ovf:DiskSection/ovf:Disk[@ovf:diskId='%s']/@ovf:fileRef" file_id in
          let file_ref = xpath_to_string expr "" in
          if file_ref == "" then error (f_"error parsing disk fileRef");
          let expr = sprintf "/ovf:Envelope/ovf:References/ovf:File[@ovf:id='%s']/@ovf:href" file_ref in
          let filename = xpath_to_string expr "" in

          (* Does the file exist and is it readable? *)
          let filename = exploded // filename in
          Unix.access filename [Unix.R_OK];

          (* The spec allows the file to be gzip-compressed, in which case
           * we must uncompress it into the tmpdir.
           *)
          let filename =
            if detect_file_type filename = `GZip then (
              let new_filename = tmpdir // string_random8 () ^ ".vmdk" in
              let cmd =
                sprintf "zcat %s > %s" (quote filename) (quote new_filename) in
              if verbose then printf "%s\n%!" cmd;
              if Sys.command cmd <> 0 then
                error (f_"error uncompressing %s, see earlier error messages")
                  filename;
              new_filename
            )
            else filename in

          let disk = {
            s_disk_id = i;
            s_qemu_uri = filename;
            s_format = Some "vmdk";
            s_controller = controller;
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

        (* XXX We assume the OVF lists these in order.
        let address = xpath_to_int "rasd:AddressOnParent/text()" 0 in
        *)

        (* Find the parent controller. *)
        let parent_id = xpath_to_int "rasd:Parent/text()" 0 in
        let controller =
          match parent_id with
          | 0 -> None
          | id -> parent_controller id in

        let typ =
          match id with
            | 14 -> Floppy
            | 15 | 16 -> CDROM
            | _ -> assert false in
        let disk = {
          s_removable_type = typ;
          s_removable_controller = controller;
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
