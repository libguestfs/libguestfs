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

(* Check the backend is not libvirt.  Works around a libvirt bug
 * (RHBZ#1134592).  This can be removed once the libvirt bug is fixed.
 *)
let error_if_libvirt_backend () =
  let libguestfs_backend = (new Guestfs.guestfs ())#get_backend () in
  if libguestfs_backend = "libvirt" then (
    error (f_"because of libvirt bug https://bugzilla.redhat.com/show_bug.cgi?id=1134592 you must set this environment variable:\n\nexport LIBGUESTFS_BACKEND=direct\n\nand then rerun the virt-v2v command.")
  )

class input_libvirt verbose libvirt_uri guest =
object
  inherit input verbose

  method as_options =
    sprintf "-i libvirt%s %s"
      (match libvirt_uri with
      | None -> ""
      | Some uri -> " -ic " ^ uri)
      guest

  method source () =
    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Domainxml.dumpxml ?conn:libvirt_uri guest in

    (* Depending on the libvirt URI we may need to convert <source/>
     * paths so we can access them remotely (if that is possible).  This
     * is only true for remote, non-NULL URIs.  (We assume the user
     * doesn't try setting $LIBVIRT_URI.  If they do that then all bets
     * are off).
     *)
    let map_source_file, map_source_dev =
      match libvirt_uri with
      | None -> None, None
      | Some orig_uri ->
        let { Xml.uri_server = server; uri_scheme = scheme } as uri =
          try Xml.parse_uri orig_uri
          with Invalid_argument msg ->
            error (f_"could not parse '-ic %s'.  Original error message was: %s")
              orig_uri msg in

        match server, scheme with
        | None, _
        | Some "", _ ->                 (* Not a remote URI. *)
          None, None

        | Some _, None                  (* No scheme? *)
        | Some _, Some "" ->
          None, None

        | Some server, Some ("esx"|"gsx"|"vpx" as scheme) -> (* ESX *)
          error_if_libvirt_backend ();
          let f = Lib_esx.map_path_to_uri verbose uri scheme server in
          Some f, Some f

        | Some server, Some ("xen+ssh" as scheme) -> (* Xen over SSH *)
          error_if_libvirt_backend ();
          let f = Lib_xen.map_path_to_uri verbose uri scheme server in
          Some f, Some f

        (* Old virt-v2v also supported qemu+ssh://.  However I am
         * deliberately not supporting this in new virt-v2v.  Don't
         * use virt-v2v if a guest already runs on KVM.
         *)
        | Some _, Some _ ->             (* Unknown remote scheme. *)
          warning ~prog (f_"no support for remote libvirt connections to '-ic %s'.  The conversion may fail when it tries to read the source disks.")
            orig_uri;
          None, None in

    Input_libvirtxml.parse_libvirt_xml ?map_source_file ?map_source_dev xml
end

let input_libvirt = new input_libvirt
let () = Modules_list.register_input_module "libvirt"
