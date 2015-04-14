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

(* xen+ssh URLs use the SSH driver in CURL.  Currently this requires
 * ssh-agent authentication.  Give a clear error if this hasn't been
 * set up (RHBZ#1139973).
 *)
let error_if_no_ssh_agent () =
  try ignore (Sys.getenv "SSH_AUTH_SOCK")
  with Not_found ->
    error (f_"ssh-agent authentication has not been set up ($SSH_AUTH_SOCK is not set).  Please read \"INPUT FROM RHEL 5 XEN\" in the virt-v2v(1) man page.")

(* Superclass. *)
class virtual input_libvirt verbose password libvirt_uri guest =
object
  inherit input verbose

  method as_options =
    sprintf "-i libvirt%s %s"
      (match libvirt_uri with
      | None -> ""
      | Some uri -> " -ic " ^ uri)
      guest
end

(* Subclass specialized for handling anything that's *not* VMware vCenter
 * or Xen.
 *)
class input_libvirt_other verbose password libvirt_uri guest =
object
  inherit input_libvirt verbose password libvirt_uri guest

  method source () =
    if verbose then printf "input_libvirt_other: source()\n%!";

    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Domainxml.dumpxml ?password ?conn:libvirt_uri guest in

    let source, disks = Input_libvirtxml.parse_libvirt_xml ?conn:libvirt_uri ~verbose xml in
    let disks =
      List.map (fun { Input_libvirtxml.p_source_disk = disk } -> disk) disks in
    { source with s_disks = disks }
end

let input_libvirt_other = new input_libvirt_other
