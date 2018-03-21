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

open Common_gettext.Gettext
open Common_utils

open Unix
open Printf

open Types
open Utils

type vdsm_options = {
  image_uuids : string list;
  vol_uuids : string list;
  vm_uuid : string;
  ovf_output : string;
  compat : string;
  ovf_flavour : OVF.ovf_flavour;
}

class output_vdsm os vdsm_options output_alloc =
object
  inherit output

  method as_options =
    sprintf "-o vdsm -os %s%s%s --vdsm-vm-uuid %s --vdsm-ovf-output %s%s%s" os
      (String.concat ""
         (List.map (sprintf " --vdsm-image-uuid %s") vdsm_options.image_uuids))
      (String.concat ""
         (List.map (sprintf " --vdsm-vol-uuid %s") vdsm_options.vol_uuids))
      vdsm_options.vm_uuid
      vdsm_options.ovf_output
      (match vdsm_options.compat with
       | "0.10" -> "" (* currently this is the default, so don't print it *)
       | s -> sprintf " --vdsm-compat=%s" s)
      (match vdsm_options.ovf_flavour with
       | OVF.OVirt -> "--vdsm-ovf-flavour=ovf"
       (* currently this is the default, so don't print it *)
       | OVF.RHVExportStorageDomain -> "")

  method supported_firmware = [ TargetBIOS ]

  (* RHV doesn't support serial consoles.  This causes the conversion
   * step to remove it.
   *)
  method keep_serial_console = false

  (* rhev-apt.exe will be installed (if available). *)
  method install_rhev_apt = true

  (* Data Domain mountpoint. *)
  val mutable dd_mp = ""
  val mutable dd_uuid = ""

  (* This is called early on in the conversion and lets us choose the
   * name of the target files that eventually get written by the main
   * code.
   *
   * 'os' is the output storage domain (-os /rhv/data/<data center>/<data domain>)
   * this is already mounted path.
   *
   * Note it's good to fail here (early) if there are any problems, since
   * the next time we are called (in {!create_metadata}) we have already
   * done the conversion and copy, and the user won't thank us for
   * displaying errors there.
   *)
  method prepare_targets _ targets =
    if List.length vdsm_options.image_uuids <> List.length targets ||
      List.length vdsm_options.vol_uuids <> List.length targets then
      error (f_"the number of '--vdsm-image-uuid' and '--vdsm-vol-uuid' parameters passed on the command line has to match the number of guest disk images (for this guest: %d)")
        (List.length targets);

    let mp, uuid =
      let fields = String.nsplit "/" os in (* ... "data-center" "UUID" *)
      let fields = List.rev fields in      (* "UUID" "data-center" ... *)
      let fields = dropwhile ((=) "") fields in
      match fields with
      | uuid :: rest when String.length uuid = 36 ->
        let mp = String.concat "/" (List.rev rest) in
        mp, uuid
      | _ ->
        error (f_"vdsm: invalid -os parameter does not contain a valid UUID: %s")
          os in

    dd_mp <- mp;
    dd_uuid <- uuid;
    debug "VDSM: DD mountpoint: %s\nVDSM: DD UUID: %s" dd_mp dd_uuid;

    (* Note that VDSM has to create all these directories. *)
    let images_dir = dd_mp // dd_uuid // "images" in
    List.iter (
      fun image_uuid ->
        let d = images_dir // image_uuid in
        if not (is_directory d) then
          error (f_"image directory (%s) does not exist or is not a directory")
            d
    ) vdsm_options.image_uuids;

    (* Note that VDSM has to create this directory too. *)
    if not (is_directory vdsm_options.ovf_output) then
      error (f_"OVF (metadata) directory (%s) does not exist or is not a directory")
        vdsm_options.ovf_output;

    debug "VDSM: OVF (metadata) directory: %s" vdsm_options.ovf_output;

    (* The final directory structure should look like this:
     *   /<MP>/<ESD_UUID>/images/
     *      <IMAGE_UUID_1>/<VOL_UUID_1>        # first disk (gen'd by main code)
     *      <IMAGE_UUID_1>/<VOL_UUID_1>.meta   # first disk
     *      <IMAGE_UUID_2>/<VOL_UUID_2>        # second disk
     *      <IMAGE_UUID_2>/<VOL_UUID_2>.meta   # second disk
     *      <IMAGE_UUID_3>/<VOL_UUID_3>        # etc
     *      <IMAGE_UUID_3>/<VOL_UUID_3>.meta   #
     *)

    (* Create the target filenames. *)
    let targets =
      List.map (
        fun ({ target_overlay = ov } as t, image_uuid, vol_uuid) ->
          let ov_sd = ov.ov_sd in
          let target_file = images_dir // image_uuid // vol_uuid in

          debug "VDSM: will export %s to %s" ov_sd target_file;

          { t with target_file = TargetFile target_file }
      ) (combine3 targets vdsm_options.image_uuids vdsm_options.vol_uuids) in

    (* Generate the .meta files associated with each volume. *)
    let metas =
      OVF.create_meta_files output_alloc dd_uuid
        vdsm_options.image_uuids targets in
    List.iter (
      fun ({ target_file = target_file }, meta) ->
        let target_file =
          match target_file with
          | TargetFile s -> s
          | TargetURI _ -> assert false in
        let meta_filename = target_file ^ ".meta" in
        with_open_out meta_filename (fun chan -> output_string chan meta)
    ) (List.combine targets metas);

    (* Return the list of targets. *)
    targets

  method disk_create ?backingfile ?backingformat ?preallocation ?compat
    ?clustersize path format size =
    let g = open_guestfs ~identifier:"vdsm_disk_create" () in
    (* For qcow2, override v2v-supplied compat option, because RHEL 6
     * nodes cannot handle qcow2 v3 (RHBZ#1145582, RHBZ#1400205).
     *)
    let compat =
      if format <> "qcow2" then compat else Some vdsm_options.compat in
    g#disk_create ?backingfile ?backingformat ?preallocation ?compat
      ?clustersize path format size

  (* This is called after conversion to write the OVF metadata. *)
  method create_metadata source targets _ guestcaps inspect target_firmware =
    (* See #supported_firmware above. *)
    assert (target_firmware = TargetBIOS);

    (* Create the metadata. *)
    let ovf = OVF.create_ovf source targets guestcaps inspect
      output_alloc dd_uuid
      vdsm_options.image_uuids
      vdsm_options.vol_uuids
      vdsm_options.vm_uuid
      vdsm_options.ovf_flavour in

    (* Write it to the metadata file. *)
    let file = vdsm_options.ovf_output // vdsm_options.vm_uuid ^ ".ovf" in
    with_open_out file (fun chan -> DOM.doc_to_chan chan ovf)
end

let output_vdsm = new output_vdsm
let () = Modules_list.register_output_module "vdsm"
