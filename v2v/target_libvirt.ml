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
open DOM

let create_libvirt_xml ?pool source overlays guestcaps =
  let memory_k = source.s_memory /^ 1024L in

  let features =
    List.filter (
      fun feature ->
        (* drop acpi if the guest doesn't support it *)
        feature <> "acpi" || guestcaps.gcaps_acpi
    ) source.s_features in

  let disks =
    let block_prefix =
      if guestcaps.gcaps_block_bus = "virtio" then "vd" else "hd" in
    List.mapi (
      fun i ov ->
        e "disk" [
          "type", if pool = None then "file" else "volume";
          "device", "disk"
        ] [
          e "driver" [
            "name", "qemu";
            "type", ov.ov_target_format;
            "cache", "none"
          ] [];
          (match pool with
          | None ->
            e "source" [
              "file", ov.ov_target_file;
            ] []
          | Some pool ->
            e "source" [
              "pool", pool;
              "volume", Filename.basename ov.ov_target_file;
            ] []
          );
          e "target" [
            "dev", block_prefix ^ (drive_name i);
            "bus", guestcaps.gcaps_block_bus;
          ] [];
        ]
    ) overlays in

  (* XXX Missing here from list of devices compared to old virt-v2v:
     <video/>
     <graphics/>
     cdroms and floppies
     network interfaces
     See: lib/Sys/VirtConvert/Connection/LibVirtTarget.pm
  *)
  let devices = disks @
  (* Standard devices added to every guest. *) [
    e "input" ["type", "tablet"; "bus", "usb"] [];
    e "input" ["type", "mouse"; "bus", "ps2"] [];
    e "console" ["type", "pty"] [];
  ] in

  let doc : doc =
    doc "domain" [
      "type", "kvm";                (* Always assume target is kvm? *)
    ] [
      e "name" [] [PCData source.s_name];
      e "memory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "currentMemory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "vcpu" [] [PCData (string_of_int source.s_vcpu)];
      e "os" [] [
        e "type" ["arch", source.s_arch] [PCData "hvm"];
      ];
      e "features" [] (List.map (fun s -> PCData s) features);

      e "on_poweroff" [] [PCData "destroy"];
      e "on_reboot" [] [PCData "restart"];
      e "on_crash" [] [PCData "restart"];

      e "devices" [] devices;
    ] (* /doc *) in

  doc

let initialize oc output_pool source overlays =
  (* Connect to output libvirt instance and check that the pool exists
   * and dump out its XML.
   *)
  let cmd =
    match oc with
    | None -> sprintf "virsh pool-dumpxml %s" (quote output_pool)
    | Some uri ->
      sprintf "virsh -c %s dumpxml %s" (quote uri) (quote output_pool) in
  let lines = external_command ~prog cmd in
  let xml = String.concat "\n" lines in
  let doc = Xml.parse_memory xml in
  let xpathctx = Xml.xpath_new_context doc in

  let xpath_to_string expr default =
    let obj = Xml.xpath_eval_expression xpathctx expr in
    if Xml.xpathobj_nr_nodes obj < 1 then default
    else (
      let node = Xml.xpathobj_node doc obj 0 in
      Xml.node_as_string node
    )
  in

  (* We can only output to a pool of type 'dir' (directory). *)
  let pool_type = xpath_to_string "/pool/@type" "" in
  if pool_type <> "dir" then
    error (f_"-o libvirt: output pool '%s' is not a directory (type='dir').  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool;
  let target_path = xpath_to_string "/pool/target/path/text()" "" in
  if target_path = "" || not (is_directory target_path) then
    error (f_"-o libvirt: output pool '%s' has type='dir' but the /pool/target/path element either does not exist or is not a local directory.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool;

  (* Set up the overlays. *)
  List.map (
    fun ov ->
      let target_file = target_path // source.s_name ^ "-" ^ ov.ov_sd in
      { ov with ov_target_file = target_file }
  ) overlays

let create_metadata oc output_pool source overlays guestcaps =
  (* We copied directly into the final pool directory.  However we
   * have to tell libvirt.
   *)
  let cmd =
    match oc with
    | None -> sprintf "virsh pool-refresh %s" (quote output_pool)
    | Some uri ->
      sprintf "virsh -c %s pool-refresh %s"
        (quote uri) (quote output_pool) in
  if Sys.command cmd <> 0 then
    warning ~prog (f_"could not refresh libvirt pool %s") output_pool;

  (* Create the metadata. *)
  let doc = create_libvirt_xml ~pool:output_pool source overlays guestcaps in

  let tmpfile, chan = Filename.open_temp_file "v2vlibvirt" ".xml" in
  DOM.doc_to_chan chan doc;
  close_out chan;

  (* Define the domain in libvirt. *)
  let cmd =
    match oc with
    | None -> sprintf "virsh define %s" (quote tmpfile)
    | Some uri ->
      sprintf "virsh -c %s define %s" (quote uri) (quote tmpfile) in
  if Sys.command cmd = 0 then (
    try Unix.unlink tmpfile with _ -> ()
  ) else (
    warning ~prog (f_"could not define libvirt domain.  The libvirt XML is still available in '%s'.  Try running 'virsh define %s' yourself instead.")
      tmpfile tmpfile
  );
