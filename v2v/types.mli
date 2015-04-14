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

(** Types. *)

type source = {
  s_dom_type : string;                  (** Source domain type, eg "kvm" *)
  s_name : string;                      (** Guest name. *)
  s_orig_name : string;                 (** Original guest name (if we rename
                                            the guest using -on, original is
                                            still saved here). *)
  s_memory : int64;                     (** Memory size (bytes). *)
  s_vcpu : int;                         (** Number of CPUs. *)
  s_features : string list;             (** Machine features. *)
  s_display : source_display option;    (** Guest display. *)
  s_disks : source_disk list;           (** Disk images. *)
  s_removables : source_removable list; (** CDROMs etc. *)
  s_nics : source_nic list;             (** NICs. *)
}
(** The source: metadata, disk images. *)

and source_disk = {
  s_disk_id : int;                      (** A unique ID for each source disk. *)
  s_qemu_uri : string;                  (** QEMU URI of source disk. *)
  s_format : string option;             (** Format. *)
  s_controller : s_controller option;   (** Controller, eg. IDE, SCSI. *)
}
(** A source disk. *)

and s_controller = Source_IDE | Source_SCSI | Source_virtio_blk
(** Source disk controller.

    For the purposes of this field, we can treat virtio-scsi as
    [SCSI].  However we don't support conversions from virtio in any
    case so virtio is here only to make it work for testing. *)

and source_removable = {
  s_removable_type : s_removable_type;  (** Type.  *)
  s_removable_controller : s_controller option; (** Controller, eg. IDE, SCSI.*)
}
(** Removable media. *)

and s_removable_type = CDROM | Floppy

and source_nic = {
  s_mac : string option;                (** MAC address. *)
  s_vnet : string;                      (** Source network name. *)
  s_vnet_orig : string;                 (** Original network (if we map it). *)
  s_vnet_type : vnet_type;              (** Source network type. *)
}
(** Network interfaces. *)
and vnet_type = Bridge | Network

and source_display = {
  s_display_type : s_display_type; (** Display type. *)
  s_keymap : string option;        (** Guest keymap. *)
  s_password : string option;      (** If required, password to access
                                       the display. *)
  s_listen : s_display_listen;     (** Listen address. *)
  s_port : int option;             (** Display port. *)
}
and s_display_type = Window | VNC | Spice
and s_display_listen =
  | LNone
  | LAddress of string             (** Listen address. *)
  | LNetwork of string             (** Listen network. *)

val string_of_source : source -> string
val string_of_source_disk : source_disk -> string

type overlay = {
  ov_overlay_file : string;  (** Local overlay file (qcow2 format). *)
  ov_sd : string;            (** "sda", "sdb" etc - canonical device name. *)
  ov_virtual_size : int64;   (** Virtual disk size in bytes. *)

  (* Note: The ov_source is for information ONLY (eg. printing
   * error messages).  It must NOT be opened/read/modified.
   *)
  ov_source : source_disk;   (** Link back to the source disk. *)
}
(** Overlay disk. *)

val string_of_overlay : overlay -> string

type target = {
  target_file : string;      (** Destination file. *)
  target_format : string;    (** Destination format (eg. -of option). *)

  (* Note that the estimate is filled in by core v2v.ml code before
   * copying starts, and the actual size is filled in after copying
   * (but may not be filled in if [--no-copy] so don't rely on it).
   *)
  target_estimated_size : int64 option; (** Est. max. space taken on target. *)
  target_actual_size : int64 option; (** Actual size on target. *)

  target_overlay : overlay;  (** Link back to the overlay disk. *)
}
(** Target disk. *)

val string_of_target : target -> string

type inspect = {
  i_root : string;                      (** Root device. *)
  i_type : string;                      (** Usual inspection fields. *)
  i_distro : string;
  i_arch : string;
  i_major_version : int;
  i_minor_version : int;
  i_package_format : string;
  i_package_management : string;
  i_product_name : string;
  i_product_variant : string;
  i_mountpoints : (string * string) list;
  i_apps : Guestfs.application2 list;   (** List of packages installed. *)
  i_apps_map : Guestfs.application2 list StringMap.t;
    (** This is a map from the app name to the application object.
        Since RPM allows multiple packages with the same name to be
        installed, the value is a list. *)
}
(** Inspection information. *)

type guestcaps = {
  gcaps_block_bus : guestcaps_block_type;
  gcaps_net_bus : guestcaps_net_type;
  gcaps_video : guestcaps_video_type;
  (** Best block device, network device and video device guest can
      access.  These are determined during conversion by inspecting the
      guest (and in some cases conversion can actually enhance these by
      installing drivers).  Thus this is not known until after
      conversion. *)

  gcaps_arch : string;      (** Architecture that KVM must emulate. *)
  gcaps_acpi : bool;        (** True if guest supports acpi. *)
}
(** Guest capabilities after conversion.  eg. Was virtio found or installed? *)

and guestcaps_block_type = Virtio_blk | IDE
and guestcaps_net_type = Virtio_net | E1000 | RTL8139
and guestcaps_video_type = QXL | Cirrus

class virtual input : bool -> object
  method virtual as_options : string
  (** Converts the input object back to the equivalent command line options.
      This is just used for pretty-printing log messages. *)
  method virtual source : unit -> source
  (** Examine the source hypervisor and create a source struct. *)
  method adjust_overlay_parameters : overlay -> unit
  (** Called just before copying to allow the input module to adjust
      parameters of the overlay disk. *)
end
(** Encapsulates all [-i], etc input arguments as an object. *)

class virtual output : bool -> object
  method virtual as_options : string
  (** Converts the output object back to the equivalent command line options.
      This is just used for pretty-printing log messages. *)
  method virtual prepare_targets : source -> target list -> target list
  (** Called before conversion to prepare the output. *)
  method check_target_free_space : source -> target list -> unit
  (** Called before conversion.  Can be used to check there is enough space
      on the target, using the [target.target_estimated_size] field. *)
  method virtual create_metadata : source -> target list -> guestcaps -> inspect -> unit
  (** Called after conversion to finish off and create metadata. *)
  method disk_create : ?backingfile:string -> ?backingformat:string -> ?preallocation:string -> ?compat:string -> ?clustersize:int -> string -> string -> int64 -> unit
  (** Called in order to create disks on the target.  The method has the
      same signature as Guestfs#disk_create. *)
  method keep_serial_console : bool
  (** Whether this output supports serial consoles (RHEV does not). *)
end
(** Encapsulates all [-o], etc output arguments as an object. *)
