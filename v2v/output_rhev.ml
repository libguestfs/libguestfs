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

let rec mount_and_check_storage_domain verbose domain_class os =
  (* The user can either specify -os nfs:/export, or a local directory
   * which is assumed to be the already-mounted NFS export.
   *)
  match string_split ":/" os with
  | mp, "" ->                         (* Already mounted directory. *)
    check_storage_domain verbose domain_class os mp
  | server, export ->
    let export = "/" ^ export in

    (* Create a mountpoint.  Default mode is too restrictive for us
     * when we need to write into the directory as 36:36.
     *)
    let mp = Mkdtemp.temp_dir "v2v." "" in
    chmod mp 0o755;

    (* Try mounting it. *)
    let cmd =
      sprintf "mount %s:%s %s" (quote server) (quote export) (quote mp) in
    if verbose then printf "%s\n%!" cmd;
    if Sys.command cmd <> 0 then
      error (f_"mount command failed, see earlier errors.\n\nThis probably means you didn't specify the right %s path [-os %s], or else you need to rerun virt-v2v as root.") domain_class os;

    (* Make sure it is unmounted at exit. *)
    at_exit (fun () ->
      let cmd = sprintf "umount %s" (quote mp) in
      if verbose then printf "%s\n%!" cmd;
      ignore (Sys.command cmd);
      try rmdir mp with _ -> ()
    );

    check_storage_domain verbose domain_class os mp

and check_storage_domain verbose domain_class os mp =
  (* Typical SD mountpoint looks like this:
   * $ ls /tmp/mnt
   * 39b6af0e-1d64-40c2-97e4-4f094f1919c7  __DIRECT_IO_TEST__  lost+found
   * $ ls /tmp/mnt/39b6af0e-1d64-40c2-97e4-4f094f1919c7
   * dom_md  images  master
   * We expect exactly one of those magic UUIDs.
   *)
  let entries =
    try Sys.readdir mp
    with Sys_error msg ->
      error (f_"could not read the %s specified by the '-os %s' parameter on the command line.  Is it really an OVirt or RHEV-M %s?  The original error is: %s") domain_class os domain_class msg in
  let entries = Array.to_list entries in
  let uuids = List.filter (
    fun entry ->
      String.length entry = 36 &&
      entry.[8] = '-' && entry.[13] = '-' && entry.[18] = '-' &&
      entry.[23] = '-'
  ) entries in
  let uuid =
    match uuids with
    | [uuid] -> uuid
    | [] ->
      error (f_"there are no UUIDs in the %s (%s).  Is it really an OVirt or RHEV-M %s?") domain_class os domain_class
    | _::_ ->
      error (f_"there are multiple UUIDs in the %s (%s).  This is unexpected, and may be a bug in virt-v2v or OVirt.") domain_class os in

  (* Check that the domain has been attached to a Data Center by
   * checking that the master/vms directory exists.
   *)
  let () =
    let master_vms_dir = mp // uuid // "master" // "vms" in
    if not (is_directory master_vms_dir) then
      error (f_"%s does not exist or is not a directory.\n\nMost likely cause: Either the %s (%s) has not been attached to any Data Center, or the path %s is not an %s at all.\n\nYou have to attach the %s to a Data Center using the RHEV-M / OVirt user interface first.\n\nIf you don't know what the %s mount point should be then you can also find this out through the RHEV-M user interface.")
        master_vms_dir domain_class os os
        domain_class domain_class domain_class in

  (* Looks good, so return the SD mountpoint and UUID. *)
  (mp, uuid)

(* UID:GID required for files and directories when writing to ESD. *)
let uid = 36 and gid = 36

class output_rhev verbose os vmtype output_alloc =
  (* Create a UID-switching handle.  If we're not root, create a dummy
   * one because we cannot switch UIDs.
   *)
  let running_as_root = geteuid () = 0 in
  let kvmuid_t =
    if running_as_root then
      Kvmuid.create ~uid ~gid ()
    else
      Kvmuid.create () in
object
  inherit output verbose

  method as_options =
    sprintf "-o rhev -os %s%s" os
      (match vmtype with
      | None -> ""
      | Some `Server -> " --vmtype server"
      | Some `Desktop -> " --vmtype desktop")

  method supported_firmware = [ TargetBIOS ]

  (* RHEV doesn't support serial consoles.  This causes the conversion
   * step to remove it.
   *)
  method keep_serial_console = false

  (* Export Storage Domain mountpoint and UUID. *)
  val mutable esd_mp = ""
  val mutable esd_uuid = ""

  (* Target VM UUID. *)
  val mutable vm_uuid = ""

  (* Image and volume UUIDs.  The length of these lists will be the
   * same as the list of targets.
   *)
  val mutable image_uuids = []
  val mutable vol_uuids = []

  (* Flag to indicate if the target image dir(s) should be deleted.
   * This is set to false once we know the conversion was
   * successful.
   *)
  val mutable delete_target_directory = true

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
    let mp, uuid =
      mount_and_check_storage_domain verbose (s_"Export Storage Domain") os in
    esd_mp <- mp;
    esd_uuid <- uuid;
    if verbose then
      eprintf "RHEV: ESD mountpoint: %s\nRHEV: ESD UUID: %s\n%!"
        esd_mp esd_uuid;

    (* See if we can write files as UID:GID 36:36. *)
    let () =
      let testfile = esd_mp // esd_uuid // string_random8 () in
      Kvmuid.make_file kvmuid_t testfile "";
      let stat = stat testfile in
      Kvmuid.unlink kvmuid_t testfile;
      let actual_uid = stat.st_uid and actual_gid = stat.st_gid in
      if verbose then
        eprintf "RHEV: actual UID:GID of new files is %d:%d\n"
          actual_uid actual_gid;
      if uid <> actual_uid || gid <> actual_gid then (
        if running_as_root then
          warning ~prog (f_"cannot write files to the NFS server as %d:%d, even though we appear to be running as root. This probably means the NFS client or idmapd is not configured properly.\n\nYou will have to chown the files that virt-v2v creates after the run, otherwise RHEV-M will not be able to import the VM.") uid gid
        else
          warning ~prog (f_"cannot write files to the NFS server as %d:%d. You might want to stop virt-v2v (^C) and rerun it as root.") uid gid
      ) in

    (* Create unique UUIDs for everything *)
    vm_uuid <- uuidgen ~prog ();
    (* Generate random image and volume UUIDs for each target. *)
    image_uuids <-
      List.map (
        fun _ -> uuidgen ~prog ()
      ) targets;
    vol_uuids <-
      List.map (
        fun _ -> uuidgen ~prog ()
      ) targets;

    (* We need to create the target image director(ies) so there's a place
     * for the main program to copy the images to.  However if image
     * conversion fails for any reason then we delete this directory.
     *)
    let images_dir = esd_mp // esd_uuid // "images" in
    List.iter (
      fun image_uuid ->
        let d = images_dir // image_uuid in
        Kvmuid.mkdir kvmuid_t d 0o755
    ) image_uuids;
    at_exit (fun () ->
      if delete_target_directory then (
        List.iter (
          fun image_uuid ->
            let d = images_dir // image_uuid in
            let cmd = sprintf "rm -rf %s" d in
            Kvmuid.command kvmuid_t cmd
        ) image_uuids
      )
    );

    (* The final directory structure should look like this:
     *   /<MP>/<ESD_UUID>/images/
     *      <IMAGE_UUID_1>/<VOL_UUID_1>        # first disk (gen'd by main code)
     *      <IMAGE_UUID_1>/<VOL_UUID_1>.meta   # first disk
     *      <IMAGE_UUID_2>/<VOL_UUID_2>        # second disk
     *      <IMAGE_UUID_2>/<VOL_UUID_2>.meta   # second disk
     *      <IMAGE_UUID_3>/<VOL_UUID_3>        # etc
     *      <IMAGE_UUID_3>/<VOL_UUID_3>.meta   #
     *)

    (* Generate the randomly named target files (just the names).
     * The main code is what generates the files themselves.
     *)
    let targets =
      List.map (
        fun ({ target_overlay = ov } as t, image_uuid, vol_uuid) ->
          let ov_sd = ov.ov_sd in
          let target_file = images_dir // image_uuid // vol_uuid in

          if verbose then
            eprintf "RHEV: will export %s to %s\n%!" ov_sd target_file;

          { t with target_file = target_file }
      ) (combine3 targets image_uuids vol_uuids) in

    (* Generate the .meta file associated with each volume. *)
    let metas =
      OVF.create_meta_files verbose output_alloc esd_uuid image_uuids
        targets in
    List.iter (
      fun ({ target_file = target_file }, meta) ->
        let meta_filename = target_file ^ ".meta" in
        Kvmuid.make_file kvmuid_t meta_filename meta
    ) (List.combine targets metas);

    (* Return the list of targets. *)
    targets

  method disk_create ?backingfile ?backingformat ?preallocation ?compat
    ?clustersize path format size =
    Kvmuid.func kvmuid_t (
      fun () ->
        let g = new Guestfs.guestfs () in
        (* For qcow2, override v2v-supplied compat option, because RHEL 6
         * nodes cannot handle qcow2 v3 (RHBZ#1145582).
         *)
        let compat = if format <> "qcow2" then compat else Some "0.10" in
        g#disk_create ?backingfile ?backingformat ?preallocation ?compat
          ?clustersize path format size;
        (* Make it sufficiently writable so that possibly root, or
         * root squashed qemu-img will definitely be able to open it.
         * An example of how root squashing nonsense makes everyone
         * less secure.
         *)
        chmod path 0o666
    )

  (* This is called after conversion to write the OVF metadata. *)
  method create_metadata source targets guestcaps inspect target_firmware =
    (* See #supported_firmware above. *)
    assert (target_firmware = TargetBIOS);

    (* Create the metadata. *)
    let ovf = OVF.create_ovf verbose source targets guestcaps inspect
      output_alloc vmtype esd_uuid image_uuids vol_uuids vm_uuid in

    (* Write it to the metadata file. *)
    let dir = esd_mp // esd_uuid // "master" // "vms" // vm_uuid in
    Kvmuid.mkdir kvmuid_t dir 0o755;
    let file = dir // vm_uuid ^ ".ovf" in
    Kvmuid.output kvmuid_t file (fun chan -> doc_to_chan chan ovf);

    (* Finished, so don't delete the target directory on exit. *)
    delete_target_directory <- false
end

let output_rhev = new output_rhev
let () = Modules_list.register_output_module "rhev"
