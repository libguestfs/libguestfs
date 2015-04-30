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

class output_glance verbose =
  (* Although glance can slurp in a stream from stdin, unfortunately
   * 'qemu-img convert' cannot write to a stream (although I guess
   * it could be implemented at least for raw).  Therefore we have
   * to write to a temporary file.  XXX
   *)
  let tmpdir =
    let base_dir = (new Guestfs.guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "glance." "" in
    rmdir_on_exit t;
    t in
object
  inherit output verbose

  method as_options = "-o glance"

  method supported_firmware = [ TargetBIOS ]

  method prepare_targets source targets =
    (* This does nothing useful except to check that the user has
     * supplied all the correct auth environment variables to make
     * 'glance' commands work as the current user.  If not then the
     * program exits early.
     *)
    if Sys.command "glance image-list > /dev/null" <> 0 then
      error (f_"glance: glance client is not installed or set up correctly.  You may need to set environment variables or source a script to enable authentication.  See preceding messages for details.");

    (* OpenStack only supports single image VMs, I think? *)
    let nr_targets = List.length targets in
    if nr_targets <> 1 then
      error (f_"glance: OpenStack conversion only supports virtual machines with a single disk image.  This VM has %d") nr_targets;

    List.map (
      fun t ->
        let target_file = tmpdir // t.target_overlay.ov_sd in
        { t with target_file = target_file }
    ) targets

  method create_metadata source targets guestcaps inspect target_firmware =
    (* See #supported_firmware above. *)
    assert (target_firmware = TargetBIOS);

    (* Upload the disk image (there should only be one - see above). *)
    let { target_file = target_file; target_format = target_format } =
      List.hd targets in
    let cmd =
      sprintf "glance image-create --name %s --disk-format=%s --container-format=bare --file %s"
        (quote source.s_name) (quote target_format) target_file in
    if verbose then printf "%s\n%!" cmd;
    if Sys.command cmd <> 0 then
      error (f_"glance: image upload to glance failed, see earlier errors");

    (* Set the properties (ie. metadata). *)
    let min_ram = source.s_memory /^ 1024L /^ 1024L in
    let properties = [
      "hw_disk_bus",
      (match guestcaps.gcaps_block_bus with
      | Virtio_blk -> "virtio"
      | IDE -> "ide");
      "hw_vif_model",
      (match guestcaps.gcaps_net_bus with
      | Virtio_net -> "virtio"
      | E1000 -> "e1000"
      | RTL8139 -> "rtl8139");
      "architecture", guestcaps.gcaps_arch;
      "hypervisor_type", "kvm";
      "vm_mode", "hvm";
      "os_type", inspect.i_type;
      "os_distro",
      (match inspect.i_distro with
      (* http://docs.openstack.org/grizzly/openstack-compute/admin/content/image-metadata.html *)
      | "archlinux" -> "arch"
      | "sles" -> "sled"
      | x -> x (* everything else is the same in libguestfs and OpenStack *)
      )
    ] in
    let properties =
      match inspect.i_major_version, inspect.i_minor_version with
      | 0, 0 -> properties
      | x, 0 -> ("os_version", string_of_int x) :: properties
      | x, y -> ("os_version", sprintf "%d.%d" x y) :: properties in

    (* Glance doesn't appear to check the properties. *)
    let cmd =
      sprintf "glance image-update --min-ram %Ld %s %s"
        min_ram
        (String.concat " " (
          List.map (
            fun (k, v) ->
              sprintf "--property %s=%s" (quote k) (quote v)
          ) properties
        ))
        (quote source.s_name) in
    if verbose then printf "%s\n%!" cmd;
    if Sys.command cmd <> 0 then (
      warning ~prog (f_"glance: failed to set image properties (ignored)");
      (* Dump out the image properties so the user can set them. *)
      printf "Image properties:\n";
      printf "  --min-ram %Ld\n" min_ram;
      List.iter (
	fun (k, v) ->
	  printf "  --property %s=%s" (quote k) (quote v)
      ) properties
    )
end

let output_glance = new output_glance
let () = Modules_list.register_output_module "glance"
