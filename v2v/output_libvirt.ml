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

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Types
open Utils
open Xpath_helpers
open Create_libvirt_xml

let arch_is_sane_or_die =
  let rex = PCRE.compile ~caseless:true "^[-_a-z0-9]+$" in
  fun arch -> assert (PCRE.matches rex arch)

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

class output_libvirt oc output_pool = object
  inherit output

  val mutable capabilities_doc = None
  val mutable pool_name = None

  method as_options =
    match oc with
    | None -> sprintf "-o libvirt -os %s" output_pool
    | Some uri -> sprintf "-o libvirt -oc %s -os %s" uri output_pool

  method prepare_targets source targets =
    (* Get the capabilities from libvirt. *)
    let xml = Libvirt_utils.capabilities ?conn:oc () in
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
    if Libvirt_utils.domain_exists ?conn:oc source.s_name then (
      if source.s_hypervisor = Physical then (* virt-p2v user *)
        error (f_"a libvirt domain called ‘%s’ already exists on the target.\n\nIf using virt-p2v, select a different ‘Name’ in the ‘Target properties’. Or delete the existing domain on the target using the ‘virsh undefine’ command.")
              source.s_name
      else                      (* !virt-p2v *)
        error (f_"a libvirt domain called ‘%s’ already exists on the target.\n\nIf using virt-v2v directly, use the ‘-on’ option to select a different name. Or delete the existing domain on the target using the ‘virsh undefine’ command.")
              source.s_name
    );

    (* Connect to output libvirt instance and check that the pool exists
     * and dump out its XML.
     *)
    let xml = Libvirt_utils.pool_dumpxml ?conn:oc output_pool in
    let doc = Xml.parse_memory xml in
    let xpathctx = Xml.xpath_new_context doc in
    let xpath_string = xpath_string xpathctx in

    (* We can only output to a pool of type 'dir' (directory). *)
    if xpath_string "/pool/@type" <> Some "dir" then
      error (f_"-o libvirt: output pool ‘%s’ is not a directory (type='dir').  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool;
    let target_path =
      match xpath_string "/pool/target/path/text()" with
      | None ->
         error (f_"-o libvirt: output pool ‘%s’ does not have /pool/target/path element.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool
      | Some dir when not (is_directory dir) ->
         error (f_"-o libvirt: output pool ‘%s’ has type='dir' but the /pool/target/path element is not a local directory.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool
      | Some dir -> dir in
    (* Get the name of the pool, since we have to use that
     * (and not the UUID) in the XML of the guest.
     *)
    let name =
      match xpath_string "/pool/name/text()" with
      | None ->
         error (f_"-o libvirt: output pool ‘%s’ does not have /pool/name element.  See virt-v2v(1) section \"OUTPUT TO LIBVIRT\"") output_pool
      | Some name -> name in
    pool_name <- Some name;

    (* Set up the targets. *)
    List.map (
      fun t ->
        let target_file =
          target_path // source.s_name ^ "-" ^ t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method supported_firmware = [ TargetBIOS; TargetUEFI ]

  method check_target_firmware guestcaps target_firmware =
    match target_firmware with
    | TargetBIOS -> ()
    | TargetUEFI ->
       (* XXX Can remove this method when libvirt supports
        * <loader type="efi"/> since then it will be up to
        * libvirt to check this.
        *)
       error_unless_uefi_firmware guestcaps.gcaps_arch

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

    let pool_name =
      match pool_name with
      | None -> output_pool
      | Some n -> n in

    (* Parse the capabilities XML in order to get the supported features. *)
    let doc =
      match capabilities_doc with
      | None -> assert false
      | Some doc -> doc in
    let target_features =
      target_features_of_capabilities_doc doc guestcaps.gcaps_arch in

    (* Create the metadata. *)
    let doc =
      create_libvirt_xml ~pool:pool_name source target_buses
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
      warning (f_"could not define libvirt domain.  The libvirt XML is still available in ‘%s’.  Try running ‘virsh define %s’ yourself instead.")
        tmpfile tmpfile
    );
end

let output_libvirt = new output_libvirt
let () = Modules_list.register_output_module "libvirt"
