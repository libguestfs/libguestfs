(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

val quote : string -> string
(** The {!Filename.quote} function. *)

val xpath_string : Xml.xpathctx -> string -> string option
val xpath_int : Xml.xpathctx -> string -> int option
val xpath_int64 : Xml.xpathctx -> string -> int64 option
(** Parse an xpath expression and return a string/int.  Returns
    [Some v], or [None] if the expression doesn't match. *)

val xpath_string_default : Xml.xpathctx -> string -> string -> string
val xpath_int_default : Xml.xpathctx -> string -> int -> int
val xpath_int64_default : Xml.xpathctx -> string -> int64 -> int64
(** Parse an xpath expression and return a string/int; if the expression
    doesn't match, return the default. *)

val drive_name : int -> string
val drive_index : string -> int

val kvm_arch : string -> string
(** Map guest architecture found by inspection to the architecture
    that KVM must emulate.  Note for x86 we assume a 64 bit hypervisor. *)

val qemu_supports_sound_card : Types.source_sound_model -> bool
(** Does qemu support the given sound card? *)

val find_uefi_firmware : string -> string * string
(** Find the UEFI firmware for the guest architecture.  Returns a
    pair [(code_file, vars_file)].  This cannot return an error, it
    calls [error] and fails instead. *)

val compare_app2_versions : Guestfs.application2 -> Guestfs.application2 -> int
(** Compare two app versions. *)

val remove_duplicates : 'a list -> 'a list
(** Remove duplicates from a list. *)
