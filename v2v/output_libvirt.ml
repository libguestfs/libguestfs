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

module StringSet = Set.Make (String)

let string_set_of_list =
  List.fold_left (fun set x -> StringSet.add x set) StringSet.empty

let arch_sanity_re = Str.regexp "^[-_A-Za-z0-9]+$"

let target_features_of_capabilities_doc doc arch =
  let xpathctx = Xml.xpath_new_context doc in
  let expr =
    (* Check the arch is sane.  It comes from untrusted input.  This
     * avoids XPath injection below.
     *)
    assert (Str.string_match arch_sanity_re arch 0);
    (* NB: Pay attention to the square brackets.  This returns the
     * <guest> nodes!
     *)
    sprintf "/capabilities/guest[arch[@name='%s']/domain/@type='kvm']" arch in
  let obj = Xml.xpath_eval_expression xpathctx expr in

  if Xml.xpathobj_nr_nodes obj < 1 then (
    (* Old virt-v2v used to die here, but that seems unfair since the
     * user has gone through conversion before we reach here.
     *)
    warning ~prog (f_"the target hypervisor does not support a %s KVM guest") arch;
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
      features := feature_name :: !features
    done;
    !features
  )

let append_child child = function
  | PCData _ | Comment _  -> assert false
  | Element e -> e.e_children <- e.e_children @ [child]

let append_attr attr = function
  | PCData _ | Comment _ -> assert false
  | Element e -> e.e_attrs <- e.e_attrs @ [attr]

let create_libvirt_xml ?pool source targets guestcaps
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
         [ e "loader" ["type", "pflash"] [ PCData code ];
           e "nvram" ["template", vars_template] [] ] in

    (e "type" ["arch", guestcaps.gcaps_arch] [PCData "hvm"]) :: loader in

  (* Disks. *)
  let disks =
    let block_prefix =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk -> "vd" | IDE -> "hd" in
    let block_bus =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk -> "virtio" | IDE -> "ide" in
    List.mapi (
      fun i t ->
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
            "dev", block_prefix ^ (drive_name i);
            "bus", block_bus;
          ] [];
        ]
    ) targets in

  let removables =
    (* CDs will be added as IDE devices if we're using virtio, else
     * they will be added as the same as the disk bus.  The original
     * s_removable_controller is ignored (same as old virt-v2v).
     *)
    let cdrom_bus, cdrom_block_prefix, cdrom_index =
      match guestcaps.gcaps_block_bus with
      | Virtio_blk | IDE -> "ide", "hd", ref 0
      (* | bus -> bus, "sd", ref (List.length targets) *) in

    (* Floppy disks always occupy their own virtual bus. *)
    let fd_bus = "fdc" and fd_index = ref 0 in

    List.map (
      function
      | { s_removable_type = CDROM } ->
        let i = !cdrom_index in
        incr cdrom_index;
        let name = cdrom_block_prefix ^ drive_name i in
        e "disk" [ "device", "cdrom"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [ "dev", name; "bus", cdrom_bus ] []
        ]

      | { s_removable_type = Floppy } ->
        let i = !fd_index in
        incr fd_index;
        let name = "fd" ^ drive_name i in
        e "disk" [ "device", "floppy"; "type", "file" ] [
          e "driver" [ "name", "qemu"; "type", "raw" ] [];
          e "target" [ "dev", name; "bus", fd_bus ] []
        ]
    ) source.s_removables in

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

  (* Same as old virt-v2v, we always add a display here even if it was
   * missing from the old metadata.
   *)
  let video, graphics =
    let video, graphics =
      match guestcaps.gcaps_video with
      | QXL ->
        e "video" [ "type", "qxl"; "ram", "65536" ] [],
        e "graphics" [ "type", "vnc" ] []
      | Cirrus ->
        e "video" [ "type", "cirrus"; "vram", "9216" ] [],
        e "graphics" [ "type", "spice" ] [] in

    append_attr ("heads", "1") video;

    (match source.s_display with
    | Some { s_keymap = Some km } -> append_attr ("keymap", km) graphics
    | _ -> ());
    (match source.s_display with
    | Some { s_password = Some pw } -> append_attr ("passwd", pw) graphics
    | _ -> ());
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
    | _ -> ());
    (match source.s_display with
    | Some { s_port = Some p } ->
      append_attr ("autoport", "no") graphics;
      append_attr ("port", string_of_int p) graphics
    | _ ->
      append_attr ("autoport", "yes") graphics;
      append_attr ("port", "-1") graphics);

    video, graphics in

  let sound =
    match source.s_sound with
    | None -> []
    | Some { s_sound_model = model } ->
       if qemu_supports_sound_card model then
         [ e "sound" [ "model", string_of_source_sound_model model ] [] ]
       else
         [] in

  let devices = disks @ removables @ nics @ [video] @ [graphics] @ sound @
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
      e "os" [] os_section;
      e "features" [] (List.map (fun s -> e s [] []) features);

      e "on_poweroff" [] [PCData "destroy"];
      e "on_reboot" [] [PCData "restart"];
      e "on_crash" [] [PCData "restart"];

      e "devices" [] devices;
    ] (* /doc *) in

  doc

class output_libvirt verbose oc output_pool = object
  inherit output verbose

  val mutable capabilities_doc = None

  method as_options =
    match oc with
    | None -> sprintf "-o libvirt -os %s" output_pool
    | Some uri -> sprintf "-o libvirt -oc %s -os %s" uri output_pool

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method prepare_targets source targets =
    (* Get the capabilities from libvirt. *)
    let xml = Domainxml.capabilities ?conn:oc () in
    if verbose then printf "libvirt capabilities XML:\n%s\n%!" xml;

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
    if Domainxml.domain_exists ?conn:oc source.s_name then
      error (f_"a libvirt domain called '%s' already exists on the target.\n\nIf using virt-v2v directly, use the '-on' option to select a different name. If using virt-p2v, select a different 'Name' in the 'Target properties'. Or delete the existing domain on the target using the 'virsh undefine' command.")
            source.s_name;

    (* Connect to output libvirt instance and check that the pool exists
     * and dump out its XML.
     *)
    let xml = Domainxml.pool_dumpxml ?conn:oc output_pool in
    let doc = Xml.parse_memory xml in
    let xpathctx = Xml.xpath_new_context doc in

    let xpath_to_string expr default =
      let obj = Xml.xpath_eval_expression xpathctx expr in
      if Xml.xpathobj_nr_nodes obj < 1 then default
      else (
        let node = Xml.xpathobj_node obj 0 in
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

    (* Set up the targets. *)
    List.map (
      fun t ->
        let target_file =
          target_path // source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method create_metadata source targets guestcaps _ target_firmware =
    (* We copied directly into the final pool directory.  However we
     * have to tell libvirt.
     *)
    let cmd =
      match oc with
      | None -> sprintf "virsh pool-refresh %s" (quote output_pool)
      | Some uri ->
        sprintf "virsh -c %s pool-refresh %s"
          (quote uri) (quote output_pool) in
    if verbose then printf "%s\n%!" cmd;
    if Sys.command cmd <> 0 then
      warning ~prog (f_"could not refresh libvirt pool %s") output_pool;

    (* Parse the capabilities XML in order to get the supported features. *)
    let doc =
      match capabilities_doc with
      | None -> assert false
      | Some doc -> doc in
    let target_features =
      target_features_of_capabilities_doc doc guestcaps.gcaps_arch in

    (* Create the metadata. *)
    let doc =
      create_libvirt_xml ~pool:output_pool source targets
        guestcaps target_features target_firmware in

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
end

let output_libvirt = new output_libvirt
let () = Modules_list.register_output_module "libvirt"
