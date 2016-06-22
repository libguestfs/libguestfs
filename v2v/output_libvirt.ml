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
open DOM

module StringSet = Set.Make (String)

let string_set_of_list =
  List.fold_left (fun set x -> StringSet.add x set) StringSet.empty

let arch_is_sane_or_die =
  let rex = Str.regexp "^[-_A-Za-z0-9]+$" in
  fun arch -> assert (Str.string_match rex arch 0)

let target_features_of_capabilities_doc doc arch =
  let xpathctx = Xml.xpath_new_context doc in
  let expr =
    (* Check the arch is sane.  It comes from untrusted input.  This
     * avoids XPath injection below.
     *)
    arch_is_sane_or_die arch;
    (* NB: Pay attention to the square brackets.  This returns the
     * <guest> nodes!
     *)
    sprintf "/capabilities/guest[arch[@name='%s']/domain/@type='kvm']" arch in
  let obj = Xml.xpath_eval_expression xpathctx expr in

  if Xml.xpathobj_nr_nodes obj < 1 then (
    (* Old virt-v2v used to die here, but that seems unfair since the
     * user has gone through conversion before we reach here.
     *)
    warning (f_"the target hypervisor does not support a %s KVM guest") arch;
    []
  ) else (
    let node (* first matching <guest> *) = Xml.xpathobj_node obj 0 in
    Xml.xpathctx_set_current_context xpathctx node;

    (* Get guest/features/* nodes. *)
    let obj = Xml.xpath_eval_expression xpathctx "features/*" in

    let features = ref [] in
    for i = 0 to Xml.xpathobj_nr_nodes obj - 1 do
      let feature_node = Xml.xpathobj_node obj i in
      let feature_name = Xml.node_name feature_node in
      push_front feature_name features
    done;
    !features
  )

let create_libvirt_xml ?pool source target_buses guestcaps
                       target_features target_firmware =
  let memory_k = source.s_memory /^ 1024L in

  (* We have the machine features of the guest when it was on the
   * source hypervisor (source.s_features).  We have the acpi flag
   * which tells us whether acpi is required by this guest
   * (guestcaps.gcaps_acpi).  And we have the set of hypervisor
   * features supported by the target (target_features).  Combine all
   * this into a final list of features.
   *)
  let features = string_set_of_list source.s_features in
  let target_features = string_set_of_list target_features in

  (* If the guest supports ACPI, add it to the output XML.  Conversely
   * if the guest does not support ACPI, then we must drop it.
   * (RHBZ#1159258)
   *)
  let features =
    if guestcaps.gcaps_acpi then
      StringSet.add "acpi" features
    else
      StringSet.remove "acpi" features in

  (* Make sure we don't add any features which are not supported by
   * the target hypervisor.
   *)
  let features = StringSet.inter(*section*) features target_features in

  (* But if the target supports apic or pae then we should add them
   * anyway (old virt-v2v did this).
   *)
  let force_features = string_set_of_list ["apic"; "pae"] in
  let force_features =
    StringSet.inter(*section*) force_features target_features in
  let features = StringSet.union features force_features in

  let features = List.sort compare (StringSet.elements features) in

  (* The <os> section subelements. *)
  let os_section =
    let loader =
      match target_firmware with
      | TargetBIOS -> []
      | TargetUEFI ->
         (* danpb is proposing that libvirt supports <loader type="efi"/>,
          * (https://bugzilla.redhat.com/show_bug.cgi?id=1217444#c6) but
          * until that day we have to use a bunch of heuristics. XXX
          *)
         let code, vars_template = find_uefi_firmware guestcaps.gcaps_arch in
         [ e "loader" ["readonly", "yes"; "type", "pflash"] [ PCData code ];
           e "nvram" ["template", vars_template] [] ] in

    (e "type" ["arch", guestcaps.gcaps_arch] [PCData "hvm"]) :: loader in

  (* The devices. *)
  let devices = ref [] in

  (* Fixed and removable disks. *)
  let disks =
    let make_disk bus_name drive_prefix i = function
    | BusSlotEmpty -> Comment (sprintf "%s slot %d is empty" bus_name i)

    | BusSlotTarget t ->
        e "disk" [
          "type", if pool = None then "file" else "volume";
          "device", "disk"
        ] [
          e "driver" [
            "name", "qemu";
            "type", t.target_format;
            "cache", "none"
          ] [];
          (match pool with
          | None ->
            e "source" [
              "file", absolute_path t.target_file;
            ] []
          | Some pool ->
            e "source" [
              "pool", pool;
              "volume", Filename.basename t.target_file;
            ] []
          );
          e "target" [
            "dev", drive_prefix ^ drive_name i;
            "bus", bus_name;
          ] [];
        ]

    | BusSlotRemovable { s_removable_type = CDROM } ->
        e "disk" [ "device", "cdrom"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [
            "dev", drive_prefix ^ drive_name i;
            "bus", bus_name
          ] []
        ]

    | BusSlotRemovable { s_removable_type = Floppy } ->
        e "disk" [ "device", "floppy"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [
            "dev", drive_prefix ^ drive_name i;
          ] []
        ]
    in

    List.flatten [
      Array.to_list
        (Array.mapi (make_disk "virtio" "vd")
                    target_buses.target_virtio_blk_bus);
      Array.to_list
        (Array.mapi (make_disk "ide" "hd")
                    target_buses.target_ide_bus);
      Array.to_list
        (Array.mapi (make_disk "scsi" "sd")
                    target_buses.target_scsi_bus);
      Array.to_list
        (Array.mapi (make_disk "floppy" "fd")
                    target_buses.target_floppy_bus)
    ] in
  append devices disks;

  let nics =
    let net_model =
      match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio" | E1000 -> "e1000" | RTL8139 -> "rtl8139" in
    List.map (
      fun { s_mac = mac; s_vnet_type = vnet_type;
            s_vnet = vnet; s_vnet_orig = vnet_orig } ->
        let vnet_type_str =
          match vnet_type with
          | Bridge -> "bridge" | Network -> "network" in

        let nic =
          let children = [
            e "source" [ vnet_type_str, vnet ] [];
            e "model" [ "type", net_model ] [];
          ] in
          let children =
            if vnet_orig <> vnet then
              Comment (sprintf "%s mapped from \"%s\" to \"%s\""
                         vnet_type_str vnet_orig vnet) :: children
            else
              children in
          e "interface" [ "type", vnet_type_str ] children in

        (match mac with
        | None -> ()
        | Some mac ->
          append_child (e "mac" [ "address", mac ] []) nic);

        nic
    ) source.s_nics in
  append devices nics;

  (* Same as old virt-v2v, we always add a display here even if it was
   * missing from the old metadata.
   *)
  let video =
    let video_model =
      match guestcaps.gcaps_video with
      | QXL ->    e "model" [ "type", "qxl"; "ram", "65536" ] []
      | Cirrus -> e "model" [ "type", "cirrus"; "vram", "9216" ] [] in
    append_attr ("heads", "1") video_model;
    e "video" [] [ video_model ] in
  push_back devices video;

  let graphics =
    match source.s_display with
    | None -> e "graphics" [ "type", "vnc" ] []
    | Some { s_display_type = Window } ->
       e "graphics" [ "type", "sdl" ] []
    | Some { s_display_type = VNC } ->
       e "graphics" [ "type", "vnc" ] []
    | Some { s_display_type = Spice } ->
       e "graphics" [ "type", "spice" ] [] in

  (match source.s_display with
   | Some { s_keymap = Some km } -> append_attr ("keymap", km) graphics
   | Some { s_keymap = None } | None -> ());
  (match source.s_display with
   | Some { s_password = Some pw } -> append_attr ("passwd", pw) graphics
   | Some { s_password = None } | None -> ());
  (match source.s_display with
   | Some { s_listen = listen } ->
      (match listen with
       | LAddress a ->
          let sub = e "listen" [ "type", "address"; "address", a ] [] in
          append_child sub graphics
       | LNetwork n ->
          let sub = e "listen" [ "type", "network"; "network", n ] [] in
          append_child sub graphics
       | LNone -> ())
   | None -> ());
  (match source.s_display with
   | Some { s_port = Some p } ->
      append_attr ("autoport", "no") graphics;
      append_attr ("port", string_of_int p) graphics
   | Some { s_port = None } | None ->
      append_attr ("autoport", "yes") graphics;
      append_attr ("port", "-1") graphics);
  push_back devices graphics;

  let sound =
    match source.s_sound with
    | None -> []
    | Some { s_sound_model = model } ->
       if qemu_supports_sound_card model then
         [ e "sound" [ "model", string_of_source_sound_model model ] [] ]
       else
         [] in
  append devices sound;

  (* Standard devices added to every guest. *)
  append devices [
    e "input" ["type", "tablet"; "bus", "usb"] [];
    e "input" ["type", "mouse"; "bus", "ps2"] [];
    e "console" ["type", "pty"] [];
  ];

  let doc : doc =
    doc "domain" [
      "type", "kvm";                (* Always assume target is kvm? *)
    ] [
      Comment generated_by;
      e "name" [] [PCData source.s_name];
      e "memory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "currentMemory" ["unit", "KiB"] [PCData (Int64.to_string memory_k)];
      e "vcpu" [] [PCData (string_of_int source.s_vcpu)];
      e "os" [] os_section;
      e "features" [] (List.map (fun s -> e s [] []) features);

      e "on_poweroff" [] [PCData "destroy"];
      e "on_reboot" [] [PCData "restart"];
      e "on_crash" [] [PCData "restart"];

      e "devices" [] !devices;
    ] in

  doc

class output_libvirt oc output_pool = object
  inherit output

  val mutable capabilities_doc = None

  method as_options =
    match oc with
    | None -> sprintf "-o libvirt -os %s" output_pool
    | Some uri -> sprintf "-o libvirt -oc %s -os %s" uri output_pool

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    (* Get the capabilities from libvirt. *)
    let xml = Domainxml.capabilities ?conn:oc () in
    debug "libvirt capabilities XML:\n%s" xml;

    (* This just checks that the capabilities XML is well-formed,
     * early so that we catch parsing errors before conversion.
     *)
    let doc = Xml.parse_memory xml in

    (* Stash the capabilities XML, since we cannot get the bits we
     * need from it until we know the guest architecture, which happens
     * after conversion.
     *)
    capabilities_doc <- Some doc;

    (* Does the domain already exist on the target?  (RHBZ#889082) *)
    if Domainxml.domain_exists ?conn:oc source.s_name then (
      if source.s_hypervisor = Physical then (* virt-p2v user *)
        error (f_"a libvirt domain called '%s' already exists on the target.\n\nIf using virt-p2v, select a different 'Name' in the 'Target properties'. Or delete the existing domain on the target using the 'virsh undefine' command.")
              source.s_name
      else                      (* !virt-p2v *)
        error (f_"a libvirt domain called '%s' already exists on the target.\n\nIf using virt-v2v directly, use the '-on' option to select a different name. Or delete the existing domain on the target using the 'virsh undefine' command.")
              source.s_name
    );

    (* Connect to output libvirt instance and check that the pool exists
     * and dump out its XML.
     *)
    let xml = Domainxml.pool_dumpxml ?conn:oc output_pool in
    let doc = Xml.parse_memory xml in
    let xpathctx = Xml.xpath_new_context doc in
    let xpath_string = xpath_string xpathctx in

    (* We can only output to a pool of type 'dir' (directory). *)
    if xpath_string "/pool/@type" <> Some "dir" then
      error (f_"-o libvirt: output pool '%s' is not a directory (type='dir').  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool;
    let target_path =
      match xpath_string "/pool/target/path/text()" with
      | None ->
         error (f_"-o libvirt: output pool '%s' does not have /pool/target/path element.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool
      | Some dir when not (is_directory dir) ->
         error (f_"-o libvirt: output pool '%s' has type='dir' but the /pool/target/path element is not a local directory.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool
      | Some dir -> dir in

    (* Set up the targets. *)
    List.map (
      fun t ->
        let target_file =
          target_path // source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method check_target_firmware guestcaps target_firmware =
    match target_firmware with
    | TargetBIOS -> ()
    | TargetUEFI ->
       (* This will fail with an error if the target firmware is
        * not installed on the host.
        * XXX Can remove this method when libvirt supports
        * <loader type="efi"/> since then it will be up to
        * libvirt to check this.
        *)
       ignore (find_uefi_firmware guestcaps.gcaps_arch)

  method create_metadata source _ target_buses guestcaps _ target_firmware =
    (* We copied directly into the final pool directory.  However we
     * have to tell libvirt.
     *)
    let cmd = [ "virsh" ] @
      (if quiet () then [ "-q" ] else []) @
      (match oc with
      | None -> []
      | Some uri -> [ "-c"; uri; ]) @
      [ "pool-refresh"; output_pool ] in
    if run_command cmd <> 0 then
      warning (f_"could not refresh libvirt pool %s") output_pool;

    (* Parse the capabilities XML in order to get the supported features. *)
    let doc =
      match capabilities_doc with
      | None -> assert false
      | Some doc -> doc in
    let target_features =
      target_features_of_capabilities_doc doc guestcaps.gcaps_arch in

    (* Create the metadata. *)
    let doc =
      create_libvirt_xml ~pool:output_pool source target_buses
        guestcaps target_features target_firmware in

    let tmpfile, chan = Filename.open_temp_file "v2vlibvirt" ".xml" in
    DOM.doc_to_chan chan doc;
    close_out chan;

    if verbose () then (
      eprintf "resulting XML for libvirt:\n%!";
      DOM.doc_to_chan stderr doc;
      eprintf "\n%!";
    );

    (* Define the domain in libvirt. *)
    let cmd = [ "virsh" ] @
      (if quiet () then [ "-q" ] else []) @
      (match oc with
      | None -> []
      | Some uri -> [ "-c"; uri; ]) @
      [ "define"; tmpfile ] in
    if run_command cmd = 0 then (
      try Unix.unlink tmpfile with _ -> ()
    ) else (
      warning (f_"could not define libvirt domain.  The libvirt XML is still available in '%s'.  Try running 'virsh define %s' yourself instead.")
        tmpfile tmpfile
    );
end

let output_libvirt = new output_libvirt
let () = Modules_list.register_output_module "libvirt"
