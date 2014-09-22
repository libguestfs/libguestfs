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
  image_uuid : string;
  vol_uuids : string list;
  vm_uuid : string;
}

class output_vdsm verbose os vdsm_params vmtype output_alloc =
object
  inherit output verbose

  method as_options =
    sprintf "-o vdsm -os %s --vdsm-image-uuid %s%s --vdsm-vm-uuid %s%s" os
      vdsm_params.image_uuid
      (String.concat ""
         (List.map (sprintf " --vdsm-vol-uuid %s") vdsm_params.vol_uuids))
      vdsm_params.vm_uuid
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

  (* Target image directory. *)
  val mutable image_dir = ""

  (* Target metadata directory. *)
  val mutable ovf_dir = ""

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
    if List.length vdsm_params.vol_uuids <> List.length targets then
      error (f_"the number of '--vdsm-vol-uuid' parameters passed on the command line has to match the number of guest disk images (for this guest: %d)")
        (List.length targets);

    let mp, uuid =
      Output_rhev.mount_and_check_storage_domain verbose (s_"Data Domain") os in
    dd_mp <- mp;
    dd_uuid <- uuid;
    if verbose then
      eprintf "VDSM: DD mountpoint: %s\nVDSM: DD UUID: %s\n%!"
        dd_mp dd_uuid;

    (* Note that VDSM has to create this directory. *)
    image_dir <- dd_mp // dd_uuid // "images" // vdsm_params.image_uuid;
    if not (is_directory image_dir) then
      error (f_"image directory (%s) does not exist or is not a directory")
        image_dir;

    if verbose then
      eprintf "VDSM: image directory: %s\n%!" image_dir;

    (* Note that VDSM has to create this directory too. *)
    ovf_dir <- dd_mp // dd_uuid // "master" // "vms" // vdsm_params.vm_uuid;
    if not (is_directory ovf_dir) then
      error (f_"OVF (metadata) directory (%s) does not exist or is not a directory")
        ovf_dir;

    if verbose then
      eprintf "VDSM: OVF (metadata) directory: %s\n%!" ovf_dir;

    (* The final directory structure should look like this:
     *   /<MP>/<ESD_UUID>/images/<IMAGE_UUID>/
     *      <VOL_UUID_1>        # first disk - will be created by main code
     *      <VOL_UUID_1>.meta   # first disk
     *      <VOL_UUID_2>        # second disk - will be created by main code
     *      <VOL_UUID_2>.meta   # second disk
     *      <VOL_UUID_3>        # etc
     *      <VOL_UUID_3>.meta   #
     *)

    (* Create the target filenames. *)
    let targets =
      List.map (
        fun ({ target_overlay = ov } as t, vol_uuid) ->
          let ov_sd = ov.ov_sd in
          let target_file = image_dir // vol_uuid in

          if verbose then
            eprintf "VDSM: will export %s to %s\n%!" ov_sd target_file;

          { t with target_file = target_file }
      ) (List.combine targets vdsm_params.vol_uuids) in

    (* Generate the .meta files associated with each volume. *)
    let metas =
      Lib_ovf.create_meta_files verbose output_alloc dd_uuid
        vdsm_params.image_uuid targets in
    List.iter (
      fun ({ target_file = target_file }, meta) ->
        let meta_filename = target_file ^ ".meta" in
        let chan = open_out meta_filename in
        output_string chan meta;
        close_out chan
    ) (List.combine targets metas);

    (* Return the list of targets. *)
    targets

  (* This is called after conversion to write the OVF metadata. *)
  method create_metadata source targets guestcaps inspect =
    (* Create the metadata. *)
    let ovf = Lib_ovf.create_ovf verbose source targets guestcaps inspect
      output_alloc vmtype dd_uuid
      vdsm_params.image_uuid
      vdsm_params.vol_uuids
      vdsm_params.vm_uuid in

    (* Write it to the metadata file. *)
    let file = ovf_dir // vdsm_params.vm_uuid ^ ".ovf" in
    let chan = open_out file in
    doc_to_chan chan ovf;
    close_out chan
end

let output_vdsm = new output_vdsm
let () = Modules_list.register_output_module "vdsm"
