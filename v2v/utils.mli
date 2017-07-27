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

(** Utilities used in virt-v2v only. *)

val uri_quote : string -> string
(** Take a string and perform %xx escaping as used in some parts of URLs. *)

val kvm_arch : string -> string
(** Map guest architecture found by inspection to the architecture
    that KVM must emulate.  Note for x86 we assume a 64 bit hypervisor. *)

val qemu_supports_sound_card : Types.source_sound_model -> bool
(** Does qemu support the given sound card? *)

val find_uefi_firmware : string -> Uefi.uefi_firmware
(** Find the UEFI firmware for the guest architecture.
    This cannot return an error, it calls [error] and fails instead. *)

val error_unless_uefi_firmware : string -> unit
(** Check UEFI firmware is installed on the local host and error out if not. *)

val compare_app2_versions : Guestfs.application2 -> Guestfs.application2 -> int
(** Compare two app versions. *)

val du : string -> int64
(** Return the true size of a file in bytes, including any wasted
    space caused by internal fragmentation (the overhead of using
    blocks).

    This can raise either [Failure] or [Invalid_argument] in case
    of errors. *)

val qemu_img_supports_offset_and_size : unit -> bool
(** Return true iff [qemu-img] supports the ["offset"] and ["size"]
    parameters to open a subset of a file. *)

val backend_is_libvirt : unit -> bool
(** Return true iff the current backend is libvirt. *)

val find_file_in_tar : string -> string -> int64 * int64
(** [find_file_in_tar tar filename] looks up file in [tar] archive and returns
    a tuple containing at which byte it starts and how long the file is.

    Function raises [Not_found] if there is no such file inside [tar] and
    [Failure] if there is any error parsing the tar output. *)
