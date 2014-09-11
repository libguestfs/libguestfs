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

let title = sprintf "Exported by virt-v2v %s" Config.package_version

type rhev_params = {
  image_uuid : string option;
  vol_uuids : string list;
  vm_uuid : string option;
  vmtype : [`Server|`Desktop] option;
}

(* Describes a mounted Export Storage Domain. *)
type export_storage_domain = {
  mp : string;                          (* Local mountpoint. *)
  uuid : string;                        (* /mp/uuid *)
}

let append_child child = function
  | PCData _ | Comment _ -> assert false
  | Element e -> e.e_children <- e.e_children @ [child]

(* We set the creation time to be the same for all dates in
 * all metadata files.
 *)
let time = time ()
let iso_time =
  let tm = gmtime time in
  sprintf "%04d/%02d/%02d %02d:%02d:%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

(* Guess vmtype based on the guest inspection data.  This is used
 * when the [--vmtype] parameter is NOT passed.
 *)
let get_vmtype = function
  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 5 && string_find product "Server" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major }
      when major >= 5 ->
    `Desktop

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 3 && string_find product "ES" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 3 && string_find product "AS" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major }
      when major >= 3 ->
    `Desktop

  | { i_type = "linux"; i_distro = "fedora" } -> `Desktop

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 1 } ->
    `Desktop                            (* Windows XP *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_product_name = product } when string_find product "XP" >= 0 ->
    `Desktop                            (* Windows XP *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2 } ->
    `Server                             (* Windows 2003 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_product_name = product } when string_find product "Server" >= 0 ->
    `Server                             (* Windows 2008 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0 } ->
    `Desktop                            (* Vista *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_product_name = product } when string_find product "Server" >= 0 ->
    `Server                             (* Windows 2008R2 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1 } ->
    `Server                             (* Windows 7 *)

  | _ -> `Server

(* Determine the ovf:OperatingSystemSection_Type from libguestfs inspection. *)
and get_ostype = function
  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "i386" } ->
    sprintf "RHEL%d" v

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "x86_64" } ->
    sprintf "RHEL%dx64" v

  | { i_type = "linux" } -> "OtherLinux"

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 1 } ->
    "WindowsXP" (* no architecture differentiation of XP on RHEV *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_product_name = product } when string_find product "XP" >= 0 ->
    "WindowsXP" (* no architecture differentiation of XP on RHEV *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_arch = "i386" } ->
    "Windows2003"

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_arch = "x86_64" } ->
    "Windows2003x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_arch = "i386" } ->
    "Windows2008"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_arch = "x86_64" } ->
    "Windows2008x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "i386" } ->
    "Windows7"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "x86_64"; i_product_variant = "Client" } ->
    "Windows7x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "x86_64" } ->
    "Windows2008R2x64"

  | { i_type = typ; i_distro = distro;
      i_major_version = major; i_minor_version = minor;
      i_product_name = product } ->
    warning ~prog (f_"unknown guest operating system: %s %s %d.%d (%s)")
      typ distro major minor product;
    "Unassigned"

class output_rhev verbose os rhev_params output_alloc =
object
  inherit output verbose

  method as_options =
    sprintf "-o rhev -os %s%s%s%s%s" os
      (match rhev_params.image_uuid with
      | None -> "" | Some uuid -> sprintf " --rhev-image-uuid %s" uuid)
      (String.concat ""
         (List.map (sprintf " --rhev-vol-uuid %s") rhev_params.vol_uuids))
      (match rhev_params.vm_uuid with
      | None -> "" | Some uuid -> sprintf " --rhev-vm-uuid %s" uuid)
      (match rhev_params.vmtype with
      | None -> ""
      | Some `Server -> " --vmtype server"
      | Some `Desktop -> " --vmtype desktop")

  (* RHEV doesn't support serial consoles.  This causes the conversion
   * step to remove it.
   *)
  method keep_serial_console = false

  (* Export Storage Domain mountpoint. *)
  val mutable esd = { mp = ""; uuid = "" }

  (* Target image directory, UUID. *)
  val mutable image_dir = ""
  val mutable image_uuid = ""

  (* Target VM UUID. *)
  val mutable vm_uuid = ""

  (* Map overlay to volume UUID.  Key is [ov_sd] field which is unique. *)
  val vol_uuid = Hashtbl.create 13

  (* Flag to indicate if the target image (image_dir) should be
   * deleted.  This is set to false once we know the conversion was
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
    let rec mount_and_check_export_storage_domain () =
      (* The user can either specify -os nfs:/export, or a local directory
       * which is assumed to be the already-mounted NFS export.  In either
       * case we need to check that we have sufficient permissions to write
       * to this mountpoint.
       *)
      match string_split ":/" os with
      | mp, "" ->                     (* Already mounted directory. *)
        check_export_storage_domain os mp
      | server, export ->
        let export = "/" ^ export in

        (* Try mounting it. *)
        let mp = Mkdtemp.temp_dir "v2v." "" in
        let cmd =
          sprintf "mount %s:%s %s" (quote server) (quote export) (quote mp) in
        if verbose then printf "%s\n%!" cmd;
        if Sys.command cmd <> 0 then
          error (f_"mount command failed, see earlier errors.\n\nThis probably means you didn't specify the right Export Storage Domain path [-os %s], or else you need to rerun virt-v2v as root.") os;

        (* Make sure it is unmounted at exit. *)
        at_exit (fun () ->
          let cmd = sprintf "umount %s" (quote mp) in
          if verbose then printf "%s\n%!" cmd;
          ignore (Sys.command cmd);
          try rmdir mp with _ -> ()
        );

        check_export_storage_domain os mp

    and check_export_storage_domain os mp =
      (* Typical ESD mountpoint looks like this:
       * $ ls /tmp/mnt
       * 39b6af0e-1d64-40c2-97e4-4f094f1919c7  __DIRECT_IO_TEST__  lost+found
       * $ ls /tmp/mnt/39b6af0e-1d64-40c2-97e4-4f094f1919c7
       * dom_md  images  master
       * We expect exactly one of those magic UUIDs.
       *)
      let entries =
        try Sys.readdir mp
        with Sys_error msg ->
          error (f_"could not read the Export Storage Domain specified by the '-os %s' parameter on the command line.  Is it really an OVirt or RHEV-M Export Storage Domain?  The original error is: %s") os msg in
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
          error (f_"there are no UUIDs in the Export Storage Domain (%s).  Is it really an OVirt or RHEV-M Export Storage Domain?") os
        | _::_ ->
          error (f_"there are multiple UUIDs in the Export Storage Domain (%s).  This is unexpected, and may be a bug in virt-v2v or OVirt.") os in

      (* Check that the domain has been attached to a Data Center by
       * checking that the master/vms directory exists.
       *)
      let () =
        let master_vms_dir = mp // uuid // "master" // "vms" in
        if not (is_directory master_vms_dir) then
          error (f_"%s does not exist or is not a directory.\n\nMost likely cause: Either the Export Storage Domain (%s) has not been attached to any Data Center, or the path %s is not an Export Storage Domain at all.\n\nYou have to attach the Export Storage Domain to a Data Center using the RHEV-M / OVirt user interface first.\n\nIf you don't know what the Export Storage Domain mount point should be then you can also find this out through the RHEV-M user interface.")
            master_vms_dir os os in

      (* Check that the ESD is writable. *)
      let testfile = mp // uuid // "v2v-write-test" in
      let write_test_failed err =
        error (f_"the Export Storage Domain (%s) is not writable.\n\nThis probably means you need to run virt-v2v as 'root'.\n\nOriginal error was: %s") os err;
      in
      (try
         let chan = open_out testfile in
         close_out chan;
         unlink testfile
       with
       | Sys_error err -> write_test_failed err
       | Unix_error (code, _, _) -> write_test_failed (error_message code)
      );

      (* Looks good, so return the ESD object. *)
      { mp = mp; uuid = uuid }
    in

    (* Create unique UUIDs for everything, either based on the command
     * line parameters or else we invent them here.
     *)
    let create_uuids () =
      image_uuid <-
        (match rhev_params.image_uuid with
        | Some uuid -> uuid
        | None -> uuidgen ~prog ());
      vm_uuid <-
        (match rhev_params.vm_uuid with
        | Some uuid -> uuid
        | None -> uuidgen ~prog ());

      (match rhev_params.vol_uuids with
      | [] ->
        (* Generate random volume UUIDs for each target. *)
        List.iter (
          fun t ->
            let uuid = uuidgen ~prog () in
            Hashtbl.replace vol_uuid t.target_overlay.ov_sd uuid
        ) targets
      | uuids ->
        (* Use the volume UUIDs passed to us on the command line. *)
        try
          List.iter (
            fun (t, uuid) ->
              Hashtbl.replace vol_uuid t.target_overlay.ov_sd uuid
          ) (List.combine targets uuids)
        with Invalid_argument _ ->
          error (f_"the number of '--rhev-vol-uuid' parameters passed on the command line has to match the number of guest disk images (for this guest: %d)")
            (List.length targets)
      )
    in

    esd <- mount_and_check_export_storage_domain ();
    if verbose then
      eprintf "RHEV: ESD mountpoint: %s\nRHEV: ESD UUID: %s\n%!"
        esd.mp esd.uuid;

    create_uuids ();

    (* We need to create the target image directory so there's a place
     * for the main program to copy the images to.  However if image
     * conversion fails for any reason then we delete this directory.
     *)
    image_dir <- esd.mp // esd.uuid // "images" // image_uuid;
    mkdir image_dir 0o755;
    at_exit (fun () ->
      if delete_target_directory then (
        let cmd = sprintf "rm -rf %s" (quote image_dir) in
        ignore (Sys.command cmd)
      )
    );
    if verbose then
      eprintf "RHEV: export directory: %s\n%!" image_dir;

    (* This loop has two purposes: (1) Generate the randomly named
     * target files (just the names).  (2) Generate the .meta file
     * associated with each volume.  At the end we have a directory
     * structure like this:
     *   /<MP>/<ESD_UUID>/images/<IMAGE_UUID>/
     *      <VOL_UUID_1>        # first disk - will be created by main code
     *      <VOL_UUID_1>.meta   # first disk
     *      <VOL_UUID_2>        # second disk - will be created by main code
     *      <VOL_UUID_2>.meta   # second disk
     *      <VOL_UUID_3>        # etc
     *      <VOL_UUID_3>.meta   #
     *)
    let targets =
      let output_alloc_for_rhev =
        match output_alloc with
        | `Sparse -> "SPARSE"
        | `Preallocated -> "PREALLOCATED" in

      List.map (
        fun ({ target_overlay = ov } as t) ->
          let ov_sd = ov.ov_sd in
          let vol_uuid =
            try Hashtbl.find vol_uuid ov_sd
            with Not_found -> assert false in
          let target_file = image_dir // vol_uuid in

          if verbose then
            eprintf "RHEV: will export %s to %s\n%!" ov_sd target_file;

          (* Create the per-volume metadata (.meta files, in an oVirt-
           * specific format).
           *)
          let vol_meta = target_file ^ ".meta" in

          let size_in_sectors =
            if ov.ov_virtual_size &^ 511L <> 0L then
              error (f_"the virtual size of the input disk %s is not an exact multiple of 512 bytes.  The virtual size is: %Ld.\n\nThis probably means something unexpected is going on, so please file a bug about this issue.")
                ov.ov_source.s_qemu_uri
                ov.ov_virtual_size;
            ov.ov_virtual_size /^ 512L in

          let format_for_rhev =
            match t.target_format with
            | "raw" -> "RAW"
            | "qcow2" -> "COW"
            | _ ->
              error (f_"RHEV does not support the output format '%s', only raw or qcow2") t.target_format in

          let chan = open_out vol_meta in
          let fpf fs = fprintf chan fs in
          fpf "DOMAIN=%s\n" esd.uuid; (* "Domain" as in Export Storage Domain *)
          fpf "VOLTYPE=LEAF\n";
          fpf "CTIME=%.0f\n" time;
          fpf "MTIME=%.0f\n" time;
          fpf "IMAGE=%s\n" image_uuid;
          fpf "DISKTYPE=1\n";
          fpf "PUUID=00000000-0000-0000-0000-000000000000\n";
          fpf "LEGALITY=LEGAL\n";
          fpf "POOL_UUID=\n";
          fpf "SIZE=%Ld\n" size_in_sectors;
          fpf "FORMAT=%s\n" format_for_rhev;
          fpf "TYPE=%s\n" output_alloc_for_rhev;
          fpf "DESCRIPTION=%s\n" title;
          fpf "EOF\n";
          close_out chan;

          { t with target_file = target_file }
      ) targets in

    (* Return the list of targets. *)
    targets

  (* This is called after conversion to write the OVF metadata. *)
  method create_metadata source targets guestcaps inspect =
    (* This modifies the OVF DOM, adding a section for each disk. *)
    let rec add_disks ovf =
      let references =
        let nodes = path_to_nodes ovf ["ovf:Envelope"; "References"] in
        match nodes with
        | [] | _::_::_ -> assert false
        | [node] -> node in
      let disk_section =
        let sections = path_to_nodes ovf ["ovf:Envelope"; "Section"] in
        try find_node_by_attr sections ("xsi:type", "ovf:DiskSection_Type")
        with Not_found -> assert false in
      let virtualhardware_section =
        let sections = path_to_nodes ovf ["ovf:Envelope"; "Content"; "Section"] in
        try find_node_by_attr sections ("xsi:type", "ovf:VirtualHardwareSection_Type")
        with Not_found -> assert false in

      (* Iterate over the disks, adding them to the OVF document. *)
      iteri (
        fun i ({ target_overlay = ov } as t) ->
          let is_boot_drive = i == 0 in

          let vol_uuid =
            try Hashtbl.find vol_uuid ov.ov_sd
            with Not_found -> assert false in

          let fileref = image_uuid // vol_uuid in

          let size_gb =
            Int64.to_float ov.ov_virtual_size /. 1024. /. 1024. /. 1024. in
          let usage_gb =
            (* In the --no-copy case it can happen that the target file
             * does not exist.  In that case we simply omit the
             * ovf:actual_size attribute.
             *)
            if Sys.file_exists t.target_file then (
              let usage_mb = du_m t.target_file in
              if usage_mb > 0L then (
                let usage_mb = Int64.to_float usage_mb /. 1024. in
                Some usage_mb
              ) else None
            ) else None in

          let format_for_rhev =
            match t.target_format with
            | "raw" -> "RAW"
            | "qcow2" -> "COW"
            | _ ->
              error (f_"RHEV does not support the output format '%s', only raw or qcow2") t.target_format in

          let output_alloc_for_rhev =
            match output_alloc with
            | `Sparse -> "SPARSE"
            | `Preallocated -> "PREALLOCATED" in

          (* Add disk to <References/> node. *)
          let disk =
            e "File" [
              "ovf:href", fileref;
              "ovf:id", vol_uuid;
              "ovf:size", Int64.to_string ov.ov_virtual_size;
              "ovf:description", title;
            ] [] in
          append_child disk references;

          (* Add disk to DiskSection. *)
          let disk =
            let attrs = [
              "ovf:diskId", vol_uuid;
              "ovf:size", sprintf "%.1f" size_gb;
              "ovf:fileRef", fileref;
              "ovf:parentRef", "";
              "ovf:vm_snapshot_id", uuidgen ~prog ();
              "ovf:volume-format", format_for_rhev;
              "ovf:volume-type", output_alloc_for_rhev;
              "ovf:format", "http://en.wikipedia.org/wiki/Byte"; (* wtf? *)
              "ovf:disk-interface",
              (match guestcaps.gcaps_block_bus with
              | Virtio_blk -> "VirtIO" | IDE -> "IDE");
              "ovf:disk-type", "System"; (* RHBZ#744538 *)
              "ovf:boot", if is_boot_drive then "True" else "False";
            ] in
            let attrs =
              match usage_gb with
              | None -> attrs
              | Some usage_gb ->
                ("ovf:actual_size", sprintf "%.1f" usage_gb) :: attrs in
            e "Disk" attrs [] in
          append_child disk disk_section;

          (* Add disk to VirtualHardware. *)
          let item =
            e "Item" [] [
              e "rasd:InstanceId" [] [PCData vol_uuid];
              e "rasd:ResourceType" [] [PCData "17"];
              e "rasd:HostResource" [] [PCData fileref];
              e "rasd:Parent" [] [PCData "00000000-0000-0000-0000-000000000000"];
              e "rasd:Template" [] [PCData "00000000-0000-0000-0000-000000000000"];
              e "rasd:ApplicationList" [] [];
              e "rasd:StorageId" [] [PCData esd.uuid];
              e "rasd:StoragePoolId" [] [PCData "00000000-0000-0000-0000-000000000000"];
              e "rasd:CreationDate" [] [PCData iso_time];
              e "rasd:LastModified" [] [PCData iso_time];
              e "rasd:last_modified_date" [] [PCData iso_time];
            ] in
          append_child item virtualhardware_section;
      ) targets

    and du_m filename =
      (* There's no OCaml binding for st_blocks, so run coreutils 'du -m'
       * to get the used size in megabytes.
       *)
      let cmd = sprintf "du -m %s | awk '{print $1}'" (quote filename) in
      let lines = external_command ~prog cmd in
      (* We really don't want the metadata generation to fail because
       * of some silly usage information, so ignore errors here.
       *)
      match lines with
      | line::_ -> (try Int64.of_string line with _ -> 0L)
      | [] -> 0L
    in

    (* This modifies the OVF DOM, adding a section for each NIC. *)
    let add_networks ovf =
      let nics = source.s_nics in
      let network_section =
        let sections = path_to_nodes ovf ["ovf:Envelope"; "Section"] in
        try find_node_by_attr sections ("xsi:type", "ovf:NetworkSection_Type")
        with Not_found -> assert false in
      let virtualhardware_section =
        let sections = path_to_nodes ovf ["ovf:Envelope"; "Content"; "Section"] in
        try find_node_by_attr sections ("xsi:type", "ovf:VirtualHardwareSection_Type")
        with Not_found -> assert false in

      (* Iterate over the NICs, adding them to the OVF document. *)
      iteri (
        fun i { s_mac = mac; s_vnet_type = vnet_type;
                s_vnet = vnet; s_vnet_orig = vnet_orig } ->
          let dev = sprintf "eth%d" i in

          let model =
            match guestcaps.gcaps_net_bus with
            | RTL8139 -> "1"
            | E1000 -> "2"
            | Virtio_net -> "3"
            (*| bus ->
              warning ~prog (f_"unknown NIC model %s for ethernet device %s.  This NIC will be imported as rtl8139 instead.")
                bus dev;
              "1" *) in

          if vnet_orig <> vnet then (
            let c = Comment (sprintf "mapped from \"%s\" to \"%s\""
                               vnet_orig vnet) in
            append_child c network_section
          );

          let network = e "Network" ["ovf:name", vnet] [] in
          append_child network network_section;

          let item =
            let children = [
              e "rasd:InstanceId" [] [PCData "3"];
              e "rasd:Caption" [] [PCData (sprintf "Ethernet adapter on %s" vnet)];
              e "rasd:ResourceType" [] [PCData "10"];
              e "rasd:ResourceSubType" [] [PCData model];
              e "rasd:Connection" [] [PCData vnet];
              e "rasd:Name" [] [PCData dev];
            ] in
            let children =
              match mac with
              | None -> children
              | Some mac -> children @ [e "rasd:MACAddress" [] [PCData mac]] in
            e "Item" [] children in
          append_child item virtualhardware_section;
      ) nics
    in

    let memsize_mb = source.s_memory /^ 1024L /^ 1024L in

    let vmtype =
      match rhev_params.vmtype with
      | Some vmtype -> vmtype
      | None -> get_vmtype inspect in
    let vmtype = match vmtype with `Desktop -> "DESKTOP" | `Server -> "SERVER" in
    let ostype = get_ostype inspect in

    let ovf : doc =
      doc "ovf:Envelope" [
        "xmlns:rasd", "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData";
        "xmlns:vssd", "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData";
        "xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance";
        "xmlns:ovf", "http://schemas.dmtf.org/ovf/envelope/1/";
        "ovf:version", "0.9"
      ] [
        e "References" [] [];
        e "Section" ["xsi:type", "ovf:NetworkSection_Type"] [
          e "Info" [] [PCData "List of networks"]
        ];
        e "Section" ["xsi:type", "ovf:DiskSection_Type"] [
          e "Info" [] [PCData "List of Virtual Disks"]
        ];
        e "Content" ["ovf:id", "out"; "xsi:type", "ovf:VirtualSystem_Type"] [
          e "Name" [] [PCData source.s_name];
          e "TemplateId" [] [PCData "00000000-0000-0000-0000-000000000000"];
          e "TemplateName" [] [PCData "Blank"];
          e "Description" [] [PCData title];
          e "Domain" [] [];
          e "CreationDate" [] [PCData iso_time];
          e "IsInitilized" [] [PCData "True"];
          e "IsAutoSuspend" [] [PCData "False"];
          e "TimeZone" [] [];
          e "IsStateless" [] [PCData "False"];
          e "Origin" [] [PCData "0"];
          e "VmType" [] [PCData vmtype];
          e "DefaultDisplayType" [] [PCData "1"];

          e "Section" ["ovf:id", vm_uuid; "ovf:required", "false";
                       "xsi:type", "ovf:OperatingSystemSection_Type"] [
            e "Info" [] [PCData "Guest Operating System"];
            e "Description" [] [PCData ostype];
          ];

          e "Section" ["xsi:type", "ovf:VirtualHardwareSection_Type"] [
            e "Info" [] [PCData (sprintf "%d CPU, %Ld Memory" source.s_vcpu memsize_mb)];
            e "Item" [] [
              e "rasd:Caption" [] [PCData (sprintf "%d virtual cpu" source.s_vcpu)];
              e "rasd:Description" [] [PCData "Number of virtual CPU"];
              e "rasd:InstanceId" [] [PCData "1"];
              e "rasd:ResourceType" [] [PCData "3"];
              e "rasd:num_of_sockets" [] [PCData (string_of_int source.s_vcpu)];
              e "rasd:cpu_per_socket"[] [PCData "1"];
            ];
            e "Item" [] [
              e "rasd:Caption" [] [PCData (sprintf "%Ld MB of memory" memsize_mb)];
              e "rasd:Description" [] [PCData "Memory Size"];
              e "rasd:InstanceId" [] [PCData "2"];
              e "rasd:ResourceType" [] [PCData "4"];
              e "rasd:AllocationUnits" [] [PCData "MegaBytes"];
              e "rasd:VirtualQuantity" [] [PCData (Int64.to_string memsize_mb)];
            ];
            e "Item" [] [
              e "rasd:Caption" [] [PCData "USB Controller"];
              e "rasd:InstanceId" [] [PCData "4"];
              e "rasd:ResourceType" [] [PCData "23"];
              e "rasd:UsbPolicy" [] [PCData "Disabled"];
            ];
            e "Item" [] [
              e "rasd:Caption" [] [PCData "Graphical Controller"];
              e "rasd:InstanceId" [] [PCData "5"];
              e "rasd:ResourceType" [] [PCData "20"];
              e "rasd:VirtualQuantity" [] [PCData "1"];
              e "rasd:Device" [] [PCData "qxl"];
            ]
          ]
        ]
      ] in

    (* Add disks to the OVF XML. *)
    add_disks ovf;

    (* Old virt-v2v ignored removable media. XXX *)

    (* Add networks to the OVF XML. *)
    add_networks ovf;

    (* Old virt-v2v didn't really look at the video and display
     * metadata, instead just adding a single standard display (see
     * above).  However it did warn if there was a password on the
     * display of the old guest.
     *)
    (match source with
    | { s_display = Some { s_password = Some _ } } ->
      warning ~prog (f_"This guest required a password for connection to its display, but this is not supported by RHEV.  Therefore the converted guest's display will not require a separate password to connect.");
    | _ -> ());

    (* Write it to the metadata file. *)
    let dir = esd.mp // esd.uuid // "master" // "vms" // vm_uuid in
    mkdir dir 0o755;
    let file = dir // vm_uuid ^ ".ovf" in
    let chan = open_out file in
    doc_to_chan chan ovf;
    close_out chan;

    (* Finished, so don't delete the target directory on exit. *)
    delete_target_directory <- false
end

let output_rhev = new output_rhev
let () = Modules_list.register_output_module "rhev"
