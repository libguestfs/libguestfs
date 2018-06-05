(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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
open Tools_utils

open Types
open Utils
open Parse_libvirt_xml

(* Libvirt < 2.1.0 did not support the "json:" pseudo-URLs that
 * we use as backingfiles, when accessing Xen over SSH or vCenter
 * over HTTPS.  Check this and print a workaround.
 *
 * We can remove this when/if we ever require libvirt >= 2.1.0 as
 * a minimum version.
 *
 * See also RHBZ#1134878.
 *)
let error_if_libvirt_does_not_support_json_backingfile () =
  if backend_is_libvirt () &&
       Libvirt_utils.libvirt_get_version () < (2, 1, 0) then
    error (f_"because of libvirt bug https://bugzilla.redhat.com/1134878 you must EITHER upgrade to libvirt >= 2.1.0 OR set this environment variable:\n\nexport LIBGUESTFS_BACKEND=direct\n\nand then rerun the virt-v2v command.")

(* Superclass. *)
class virtual input_libvirt input_conn (input_password : string option) guest =
object
  inherit input

  method as_options =
    sprintf "-i libvirt%s %s"
      (match input_conn with
      | None -> ""
      | Some uri -> " -ic " ^ uri)
      guest
end

(* Subclass specialized for handling anything that's *not* VMware vCenter
 * or Xen.
 *)
class input_libvirt_other input_conn input_password guest =
object
  inherit input_libvirt input_conn input_password guest

  method source () =
    debug "input_libvirt_other: source ()";

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Libvirt_utils.dumpxml ?password_file:input_password
                                    ?conn:input_conn guest in

    let source, disks = parse_libvirt_xml ?conn:input_conn xml in
    let disks = List.map (fun { p_source_disk = disk } -> disk) disks in
    { source with s_disks = disks }
end

let input_libvirt_other = new input_libvirt_other
