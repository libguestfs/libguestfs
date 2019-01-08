(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(** [-i libvirt] source. *)

open Printf

open Common_gettext.Gettext
open Tools_utils

open Types
open Utils

(* Choose the right subclass based on the URI. *)
let input_libvirt input_conn input_password input_transport guest =
  match input_conn with
  | None ->
    Input_libvirt_other.input_libvirt_other input_conn input_password guest

  | Some orig_uri ->
    let { Xml.uri_server = server; uri_scheme = scheme } as parsed_uri =
      try Xml.parse_uri orig_uri
      with Invalid_argument msg ->
        error (f_"could not parse '-ic %s'.  Original error message was: %s")
          orig_uri msg in

    match server, scheme, input_transport with
    | None, _, _
    | Some "", _, _                     (* Not a remote URI. *)

    | Some _, None, _                   (* No scheme? *)
    | Some _, Some "", _ ->
      Input_libvirt_other.input_libvirt_other input_conn input_password guest

    (* vCenter over https. *)
    | Some server, Some ("esx"|"gsx"|"vpx"), None ->
       Input_libvirt_vcenter_https.input_libvirt_vcenter_https
         input_conn input_password parsed_uri server guest

    (* vCenter or ESXi using nbdkit vddk plugin *)
    | Some server, Some ("esx"|"gsx"|"vpx"), Some (`VDDK vddk_options) ->
       Input_libvirt_vddk.input_libvirt_vddk input_conn input_password
                                             vddk_options parsed_uri guest

    (* Xen over SSH *)
    | Some server, Some "xen+ssh", _ ->
      Input_libvirt_xen_ssh.input_libvirt_xen_ssh
        input_conn input_password parsed_uri server guest

    (* Old virt-v2v also supported qemu+ssh://.  However I am
     * deliberately not supporting this in new virt-v2v.  Don't
     * use virt-v2v if a guest already runs on KVM.
     *)

    (* Unknown remote scheme. *)
    | Some _, Some _, _ ->
      warning (f_"no support for remote libvirt connections to '-ic %s'.  The conversion may fail when it tries to read the source disks.")
        orig_uri;
      Input_libvirt_other.input_libvirt_other input_conn input_password guest

let () = Modules_list.register_input_module "libvirt"
