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

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Types
open Parse_libvirt_xml

class input_libvirtxml file =
object
  inherit input

  method as_options = "-i libvirtxml " ^ file

  method source () =
    let xml = read_whole_file file in

    let source, disks = parse_libvirt_xml xml in

    (* When reading libvirt XML from a file (-i libvirtxml) we allow
     * paths to disk images in the libvirt XML to be relative (to the XML
     * file).  Relative paths are in fact not permitted in real libvirt
     * XML, but they are very useful when dealing with test images or
     * when writing the XML by hand.
     *)
    let dir = Filename.dirname (absolute_path file) in
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } -> disk
      | { p_source_disk = disk; p_source = P_source_dev _ } -> disk
      | { p_source_disk = disk; p_source = P_source_file path } ->
        let path =
          if not (Filename.is_relative path) then path else dir // path in
        { disk with s_qemu_uri = path }
    ) disks in

    { source with s_disks = disks }
end

let input_libvirtxml = new input_libvirtxml
let () = Modules_list.register_input_module "libvirtxml"
