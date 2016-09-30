(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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
open Xpath_helpers
open Name_from_disk

class input_ova ova =
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "ova." "" in
    rmdir_on_exit t;
    t in
object
  inherit input

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
          let b = Bytes.create 512 in
          let len = input chan_out b 0 (Bytes.length b) in
          (* We're expecting the subprocess to fail because we close
           * the pipe early, so:
           *)
          ignore (Unix.close_process_full (chan_out, chan_in, chan_err));

          let tmpfile, chan = Filename.open_temp_file ~temp_dir:tmpdir "ova.file." "" in
          output chan b 0 len;
          close_out chan;

          tmpfile in

        let untar ?(format = "") file outdir =
          let cmd = [ "tar"; sprintf "-x%sf" format; file; "-C"; outdir ] in
          if run_command cmd <> 0 then
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
          let cmd = [ "unzip" ] @
            (if verbose () then [] else [ "-q" ]) @
            [ "-j"; "-d"; tmpdir; ova ] in
          if run_command cmd <> 0 then
            error (f_"error unpacking %s, see earlier error messages") ova;
          tmpdir
        | (`GZip|`XZ) as format ->
          let zcat, tar_fmt =
            match format with
            | `GZip -> "zcat", "z"
            | `XZ -> "xzcat", "J" in
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
    let exploded = absolute_path exploded in

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
        let mf_folder = Filename.dirname mf in
        let chan = open_in mf in
        let rec loop () =
          let line = input_line chan in
          if Str.string_match rex line 0 then (
            let disk = Str.matched_group 1 line in
            let expected = Str.matched_group 2 line in
            let csum = Checksums.SHA1 expected in
            try Checksums.verify_checksum csum (mf_folder // disk)
            with Checksums.Mismatched_checksum (_, actual) ->
              error (f_"checksum of disk %s does not match manifest %s (actual sha1(%s) = %s, expected sha1 (%s) = %s)")
                disk mf disk actual disk expected;
          )
        in
        (try loop () with End_of_file -> ());
        close_in chan
    ) mf;

    (* Parse the ovf file. *)
    let ovf_folder = Filename.dirname ovf in
    let xml = read_whole_file ovf in
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
    and xpath_string_default = xpath_string_default xpathctx
    and xpath_int_default = xpath_int_default xpathctx
    and xpath_int64_default = xpath_int64_default xpathctx in

    (* Search for vm name. *)
    let name =
      match xpath_string "/ovf:Envelope/ovf:VirtualSystem/ovf:Name/text()" with
      | None | Some "" ->
        warning (f_"could not parse ovf:Name from OVF document");
        name_from_disk ova
      | Some name -> name in

    (* Search for memory. *)
    let memory = xpath_int64_default "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=4]/rasd:VirtualQuantity/text()" (1024L *^ 1024L) in
    let memory = memory *^ 1024L *^ 1024L in

    (* Search for number of vCPUs. *)
    let vcpu = xpath_int_default "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=3]/rasd:VirtualQuantity/text()" 1 in

    (* BIOS or EFI firmware? *)
    let firmware = xpath_string_default "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/vmw:Config[@vmw:key=\"firmware\"]/@vmw:value" "bios" in
    let firmware =
      match firmware with
      | "bios" -> BIOS
      | "efi" -> UEFI
      | s ->
         error (f_"unknown Config:firmware value %s (expected \"bios\" or \"efi\")") s in

    (* Helper function to return the parent controller of a disk. *)
    let parent_controller id =
      let expr = sprintf "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:InstanceID/text()=%d]/rasd:ResourceType/text()" id in
      let controller = xpath_int expr in

      (* 6: iscsi controller, 5: ide *)
      match controller with
      | Some 6 -> Some Source_SCSI
      | Some 5 -> Some Source_IDE
      | None ->
        warning (f_"ova disk has no parent controller, please report this as a bug supplying the *.ovf file extracted from the ova");
        None
      | Some controller ->
        warning (f_"ova disk has an unknown VMware controller type (%d), please report this as a bug supplying the *.ovf file extracted from the ova")
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
        let file_id = xpath_string_default "rasd:HostResource/text()" "" in
        let rex = Str.regexp "^\\(ovf:\\)?/disk/\\(.*\\)" in
        if Str.string_match rex file_id 0 then (
          (* Chase the references through to the actual file name. *)
          let file_id = Str.matched_group 2 file_id in
          let expr = sprintf "/ovf:Envelope/ovf:DiskSection/ovf:Disk[@ovf:diskId='%s']/@ovf:fileRef" file_id in
          let file_ref =
            match xpath_string expr with
            | None -> error (f_"error parsing disk fileRef")
            | Some s -> s in
          let expr = sprintf "/ovf:Envelope/ovf:References/ovf:File[@ovf:id='%s']/@ovf:href" file_ref in
          let filename =
            match xpath_string expr with
            | None -> error (f_"no href in ovf:File (id=%s)") file_ref
            | Some s -> s in

          (* Does the file exist and is it readable? *)
          let filename = ovf_folder // filename in
          Unix.access filename [Unix.R_OK];

          (* The spec allows the file to be gzip-compressed, in which case
           * we must uncompress it into the tmpdir.
           *)
          let filename =
            if detect_file_type filename = `GZip then (
              let new_filename = tmpdir // String.random8 () ^ ".vmdk" in
              let cmd =
                sprintf "zcat %s > %s" (quote filename) (quote new_filename) in
              if shell_command cmd <> 0 then
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
          push_front disk disks;
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
        push_front disk removables;
      done in
    let removables = List.rev !removables in

    (* Search for networks ResourceType: 10 *)
    let nics = ref [] in
    let obj = Xml.xpath_eval_expression xpathctx "/ovf:Envelope/ovf:VirtualSystem/ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType/text()=10]"  in
    let nr_nodes = Xml.xpathobj_nr_nodes obj in
    for i = 0 to nr_nodes-1 do
      let n = Xml.xpathobj_node obj i in
      Xml.xpathctx_set_current_context xpathctx n;
      let vnet =
        xpath_string_default "rasd:ElementName/text()" (sprintf"eth%d" i) in
      let nic = {
        s_mac = None;
        s_nic_model = None;
        s_vnet = vnet;
        s_vnet_orig = vnet;
        s_vnet_type = Network;
      } in
      push_front nic nics
    done;

    let source = {
      s_hypervisor = VMware;
      s_name = name;
      s_orig_name = name;
      s_memory = memory;
      s_vcpu = vcpu;
      s_features = []; (* XXX *)
      s_firmware = firmware;
      s_display = None; (* XXX *)
      s_video = None;
      s_sound = None;
      s_disks = disks;
      s_removables = removables;
      s_nics = List.rev !nics;
    } in

    source
end

let input_ova = new input_ova
let () = Modules_list.register_input_module "ova"
