(* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED
 *          from the code in the generator/ subdirectory.
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 *
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

(** UEFI paths. *)

type uefi_firmware = {
  code : string;                (** code file *)
  code_debug : string option;   (** code debug file *)
  vars : string;                (** vars template file *)
  flags : uefi_flags;           (** flags *)
}
and uefi_flags = uefi_flag list
and uefi_flag = UEFI_FLAG_SECURE_BOOT_REQUIRED

val uefi_aarch64_firmware : uefi_firmware list
val uefi_x86_64_firmware : uefi_firmware list
