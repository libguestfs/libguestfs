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

open Common_gettext.Gettext
open Common_utils

open Unix
open Printf

open Types
open Utils
open DOM

type vdsm_params = {
  image_uuids : string list;
  vol_uuids : string list;
  vm_uuid : string;
  ovf_output : string;
}

class output_vdsm verbose os vdsm_params vmtype output_alloc =
object
  inherit output verbose

  method as_options =
    sprintf "-o vdsm -os %s%s%s --vdsm-vm-uuid %s --vdsm-ovf-output %s%s" os
      (String.concat ""
         (List.map (sprintf " --vdsm-image-uuid %s") vdsm_params.image_uuids))
      (String.concat ""
         (List.map (sprintf " --vdsm-vol-uuid %s") vdsm_params.vol_uuids))
      vdsm_params.vm_uuid
      vdsm_params.ovf_output
      (match vmtype with
      | None -> ""
      | Some `Server -> " --vmtype server"
      | Some `Desktop -> " --vmtype desktop")

  (* RHEV doesn't support serial consoles.  This causes the conversion
   * step to remove it.
   *)
  method keep_serial_console = false

  (* Data Domain mountpoint. *)
  val mutable dd_mp = ""
  val mutable dd_uuid = ""

  (* This is called early on in the conversion and lets us choose the
   * name of the target files that eventually get written by the main
   * code.
   *
   * 'os' is the output storage (-os nfs:/export).  'source' contains a
   * few useful fields such as the guest name.  'targets' describes the
   * destination files.  We modify and return this list.
   *
   * Note it's good to fail here (early) if there are any problems, since
   * the next time we are called (in {!create_metadata}) we have already
   * done the conversion and copy, and the user won't thank us for
   * displaying errors there.
   *)
  method prepare_targets _ targets =
    if List.length vdsm_params.image_uuids <> List.length targets ||
      List.length vdsm_params.vol_uuids <> List.length targets then
      error (f_"the number of '--vdsm-image-uuid' and '--vdsm-vol-uuid' parameters passed on the command line has to match the number of guest disk images (for this guest: %d)")
        (List.length targets);

    let mp, uuid =
      Output_rhev.mount_and_check_storage_domain verbose (s_"Data Domain") os in
    dd_mp <- mp;
    dd_uuid <- uuid;
    if verbose then
      eprintf "VDSM: DD mountpoint: %s\nVDSM: DD UUID: %s\n%!"
        dd_mp dd_uuid;

    (* Note that VDSM has to create all these directories. *)
    let images_dir = dd_mp // dd_uuid // "images" in
    List.iter (
      fun image_uuid ->
        let d = images_dir // image_uuid in
        if not (is_directory d) then
          error (f_"image directory (%s) does not exist or is not a directory")
            d
    ) vdsm_params.image_uuids;

    (* Note that VDSM has to create this directory too. *)
    if not (is_directory vdsm_params.ovf_output) then
      error (f_"OVF (metadata) directory (%s) does not exist or is not a directory")
        vdsm_params.ovf_output;

    if verbose then
      eprintf "VDSM: OVF (metadata) directory: %s\n%!" vdsm_params.ovf_output;

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

          if verbose then
            eprintf "VDSM: will export %s to %s\n%!" ov_sd target_file;

          { t with target_file = target_file }
      ) (combine3 targets vdsm_params.image_uuids vdsm_params.vol_uuids) in

    (* Generate the .meta files associated with each volume. *)
    let metas =
      OVF.create_meta_files verbose output_alloc dd_uuid
        vdsm_params.image_uuids targets in
    List.iter (
      fun ({ target_file = target_file }, meta) ->
        let meta_filename = target_file ^ ".meta" in
        let chan = open_out meta_filename in
        output_string chan meta;
        close_out chan
    ) (List.combine targets metas);

    (* Return the list of targets. *)
    targets

  method disk_create ?backingfile ?backingformat ?preallocation ?compat
    ?clustersize path format size =
    let g = new Guestfs.guestfs () in
    (* For qcow2, override v2v-supplied compat option, because RHEL 6
     * nodes cannot handle qcow2 v3 (RHBZ#1145582).
     *)
    let compat = if format <> "qcow2" then compat else Some "0.10" in
    g#disk_create ?backingfile ?backingformat ?preallocation ?compat
      ?clustersize path format size

  (* This is called after conversion to write the OVF metadata. *)
  method create_metadata source targets guestcaps inspect =
    (* Create the metadata. *)
    let ovf = OVF.create_ovf verbose source targets guestcaps inspect
      output_alloc vmtype dd_uuid
      vdsm_params.image_uuids
      vdsm_params.vol_uuids
      vdsm_params.vm_uuid in

    (* Write it to the metadata file. *)
    let file = vdsm_params.ovf_output // vdsm_params.vm_uuid ^ ".ovf" in
    let chan = open_out file in
    doc_to_chan chan ovf;
    close_out chan
end

let output_vdsm = new output_vdsm
let () = Modules_list.register_output_module "vdsm"
