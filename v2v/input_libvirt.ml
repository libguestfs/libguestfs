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

(** [-i libvirt] source. *)

open Printf

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

(* Choose the right subclass based on the URI. *)
let input_libvirt verbose password libvirt_uri guest =
  match libvirt_uri with
  | None ->
    Input_libvirt_other.input_libvirt_other verbose password libvirt_uri guest

  | Some orig_uri ->
    let { Xml.uri_server = server; uri_scheme = scheme } as parsed_uri =
      try Xml.parse_uri orig_uri
      with Invalid_argument msg ->
        error (f_"could not parse '-ic %s'.  Original error message was: %s")
          orig_uri msg in

    match server, scheme with
    | None, _
    | Some "", _                        (* Not a remote URI. *)

    | Some _, None                      (* No scheme? *)
    | Some _, Some "" ->
      Input_libvirt_other.input_libvirt_other verbose password libvirt_uri guest

    | Some server, Some ("esx"|"gsx"|"vpx" as scheme) -> (* vCenter over https *)
      Input_libvirt_vcenter_https.input_libvirt_vcenter_https
        verbose password libvirt_uri parsed_uri scheme server guest

    | Some server, Some ("xen+ssh" as scheme) -> (* Xen over SSH *)
      Input_libvirt_xen_ssh.input_libvirt_xen_ssh
        verbose password libvirt_uri parsed_uri scheme server guest

    (* Old virt-v2v also supported qemu+ssh://.  However I am
     * deliberately not supporting this in new virt-v2v.  Don't
     * use virt-v2v if a guest already runs on KVM.
     *)

    | Some _, Some _ ->             (* Unknown remote scheme. *)
      warning (f_"no support for remote libvirt connections to '-ic %s'.  The conversion may fail when it tries to read the source disks.")
        orig_uri;
      Input_libvirt_other.input_libvirt_other verbose password libvirt_uri guest

let () = Modules_list.register_input_module "libvirt"
