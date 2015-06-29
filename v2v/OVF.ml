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

(* Functions for dealing with OVF files. *)

open Common_gettext.Gettext
open Common_utils

open Unix
open Printf

open Types
open Utils
open DOM

let title = sprintf "Exported by virt-v2v %s" Config.package_version

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

(* Determine the ovf:OperatingSystemSection_Type from libguestfs
 * inspection.  See ovirt-engine sources, file:
 *   packaging/conf/osinfo-defaults.properties
 * and also:
 *   https://bugzilla.redhat.com/show_bug.cgi?id=1219857#c9
 *)
and get_ostype = function
  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "i386" } when v <= 6 ->
    sprintf "RHEL%d" v

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "x86_64" } when v <= 6 ->
    sprintf "RHEL%dx64" v

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "x86_64" } (* when v >= 7 *) ->
    sprintf "rhel_%dx64" v

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = 7;
      i_arch = "ppc64" | "ppc64le" } ->
    "rhel_7_ppc64"

  | { i_type = "linux"; i_distro = "sles"; i_major_version = 11;
      i_arch = "x86_64" } ->
    "sles_11"

  | { i_type = "linux"; i_distro = "sles"; i_major_version = 11;
      i_arch = "ppc64" | "ppc64le" } ->
    "sles_11_ppc64"

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

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 2;
      i_arch = "i386" } ->
    "windows_8"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 2;
      i_arch = "x86_64"; i_product_variant = "Client" } ->
    "windows_8x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 2;
      i_arch = "x86_64" } ->
    "windows_2012x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 3;
      i_arch = "x86_64" } ->
    "windows_2012R2x64"

  | { i_type = typ; i_distro = distro;
      i_major_version = major; i_minor_version = minor;
      i_product_name = product } ->
    warning ~prog (f_"unknown guest operating system: %s %s %d.%d (%s)")
      typ distro major minor product;
    "Unassigned"

(* Generate the .meta file associated with each volume. *)
let create_meta_files verbose output_alloc sd_uuid image_uuids targets =
  (* Note: Upper case in the .meta, mixed case in the OVF. *)
  let output_alloc_for_rhev =
    match output_alloc with
    | `Sparse -> "SPARSE"
    | `Preallocated -> "PREALLOCATED" in

  List.map (
    fun ({ target_overlay = ov } as t, image_uuid) ->
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

      let buf = Buffer.create 256 in
      let bpf fs = bprintf buf fs in
      bpf "DOMAIN=%s\n" sd_uuid; (* "Domain" as in Storage Domain *)
      bpf "VOLTYPE=LEAF\n";
      bpf "CTIME=%.0f\n" time;
      bpf "MTIME=%.0f\n" time;
      bpf "IMAGE=%s\n" image_uuid;
      bpf "DISKTYPE=1\n";
      bpf "PUUID=00000000-0000-0000-0000-000000000000\n";
      bpf "LEGALITY=LEGAL\n";
      bpf "POOL_UUID=\n";
      bpf "SIZE=%Ld\n" size_in_sectors;
      bpf "FORMAT=%s\n" format_for_rhev;
      bpf "TYPE=%s\n" output_alloc_for_rhev;
      bpf "DESCRIPTION=%s\n" title;
      bpf "EOF\n";
      Buffer.contents buf
  ) (List.combine targets image_uuids)

(* Create the OVF file. *)
let rec create_ovf verbose source targets guestcaps inspect
    output_alloc vmtype sd_uuid image_uuids vol_uuids vm_uuid =
  assert (List.length targets = List.length vol_uuids);

  let memsize_mb = source.s_memory /^ 1024L /^ 1024L in

  let vmtype =
    match vmtype with
      | Some vmtype -> vmtype
      | None -> get_vmtype inspect in
  let vmtype = match vmtype with `Desktop -> "0" | `Server -> "1" in
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
  add_disks targets guestcaps output_alloc sd_uuid image_uuids vol_uuids ovf;

  (* Old virt-v2v ignored removable media. XXX *)

  (* Add networks to the OVF XML. *)
  add_networks source.s_nics guestcaps ovf;

  (* Old virt-v2v didn't really look at the video and display
   * metadata, instead just adding a single standard display (see
   * above).  However it did warn if there was a password on the
   * display of the old guest.
   *)
  (match source with
  | { s_display = Some { s_password = Some _ } } ->
    warning ~prog (f_"This guest required a password for connection to its display, but this is not supported by RHEV.  Therefore the converted guest's display will not require a separate password to connect.");
    | _ -> ());

  (* Return the OVF document. *)
  ovf

and append_child child = function
  | PCData _ | Comment _ -> assert false
  | Element e -> e.e_children <- e.e_children @ [child]

(* This modifies the OVF DOM, adding a section for each disk. *)
and add_disks targets guestcaps output_alloc sd_uuid image_uuids vol_uuids ovf =
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
    fun i ({ target_overlay = ov } as t, image_uuid, vol_uuid) ->
      let is_boot_drive = i == 0 in

      let fileref = image_uuid // vol_uuid in

      (* ovf:size and ovf:actual_size fields are integer GBs.  If you
       * use floating point numbers then RHEV will fail to parse them.
       * In case the size is just below a gigabyte boundary, round up.
       *)
      let bytes_to_gb b =
        let b = roundup64 b 1073741824L in
        b /^ 1073741824L
      in
      let size_gb = bytes_to_gb ov.ov_virtual_size in
      let actual_size_gb, is_estimate =
        match t.target_actual_size, t.target_estimated_size with
        | Some actual_size, _ -> Some (bytes_to_gb actual_size), false
          (* In the --no-copy case the target file does not exist.  In
           * that case we use the estimated size.
           *)
        | None, Some estimated_size -> Some (bytes_to_gb estimated_size), true
        | None, None -> None, false in

      let format_for_rhev =
        match t.target_format with
        | "raw" -> "RAW"
        | "qcow2" -> "COW"
        | _ ->
          error (f_"RHEV does not support the output format '%s', only raw or qcow2") t.target_format in

      (* Note: Upper case in the .meta, mixed case in the OVF. *)
      let output_alloc_for_rhev =
        match output_alloc with
        | `Sparse -> "Sparse"
        | `Preallocated -> "Preallocated" in

      (* Add disk to <References/> node. *)
      let disk =
        e "File" [
          "ovf:href", fileref;
          "ovf:id", vol_uuid;
          "ovf:size", Int64.to_string ov.ov_virtual_size; (* NB: in bytes *)
          "ovf:description", title;
        ] [] in
      append_child disk references;

      (* Add disk to DiskSection. *)
      let disk =
        let attrs = [
          "ovf:diskId", vol_uuid;
          "ovf:size", Int64.to_string size_gb;
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
          match actual_size_gb with
          | None -> attrs
          | Some actual_size_gb ->
            ("ovf:actual_size", Int64.to_string actual_size_gb) :: attrs in
        e "Disk" attrs [] in
      if is_estimate then (
        let comment = Comment "note: actual_size field is estimated" in
        append_child comment disk_section
      );
      append_child disk disk_section;

      (* Add disk to VirtualHardware. *)
      let item =
        (* This text MUST begin with the string "Drive " or the file
         * will not parse.
         *)
        let caption = sprintf "Drive %d" (i+1) in
        e "Item" [] [
          e "rasd:Caption" [] [PCData caption];
          e "rasd:InstanceId" [] [PCData vol_uuid];
          e "rasd:ResourceType" [] [PCData "17"];
          e "rasd:HostResource" [] [PCData fileref];
          e "rasd:Parent" [] [PCData "00000000-0000-0000-0000-000000000000"];
          e "rasd:Template" [] [PCData "00000000-0000-0000-0000-000000000000"];
          e "rasd:ApplicationList" [] [];
          e "rasd:StorageId" [] [PCData sd_uuid];
          e "rasd:StoragePoolId" [] [PCData "00000000-0000-0000-0000-000000000000"];
          e "rasd:CreationDate" [] [PCData iso_time];
          e "rasd:LastModified" [] [PCData iso_time];
          e "rasd:last_modified_date" [] [PCData iso_time];
        ] in
      append_child item virtualhardware_section;
  ) (combine3 targets image_uuids vol_uuids)

(* This modifies the OVF DOM, adding a section for each NIC. *)
and add_networks nics guestcaps ovf =
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
        let c =
          Comment (sprintf "mapped from \"%s\" to \"%s\"" vnet_orig vnet) in
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
