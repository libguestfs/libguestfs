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

(* Functions for dealing with OVF files. *)

open Common_gettext.Gettext
open Common_utils

open Types
open Utils

open Printf

(* Guess vmtype based on the guest inspection data.  This is used
 * when the [--vmtype] parameter is NOT passed.
 *)
let ovf_vmtype = function
  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 5 && string_find product "Server" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major }
      when major >= 5 ->
    `Desktop

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 3 && string_find product "ES" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major;
      i_product_name = product }
      when major >= 3 && string_find product "AS" >= 0 ->
    `Server

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = major }
      when major >= 3 ->
    `Desktop

  | { i_type = "linux"; i_distro = "fedora" } -> `Desktop

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 1 } ->
    `Desktop                            (* Windows XP *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_product_name = product } when string_find product "XP" >= 0 ->
    `Desktop                            (* Windows XP *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2 } ->
    `Server                             (* Windows 2003 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_product_name = product } when string_find product "Server" >= 0 ->
    `Server                             (* Windows 2008 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0 } ->
    `Desktop                            (* Vista *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_product_name = product } when string_find product "Server" >= 0 ->
    `Server                             (* Windows 2008R2 *)

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1 } ->
    `Server                             (* Windows 7 *)

  | _ -> `Server

(* Determine the ovf:OperatingSystemSection_Type from libguestfs inspection. *)
and ovf_ostype = function
  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "i386" } ->
    sprintf "RHEL%d" v

  | { i_type = "linux"; i_distro = "rhel"; i_major_version = v;
      i_arch = "x86_64" } ->
    sprintf "RHEL%dx64" v

  | { i_type = "linux" } -> "OtherLinux"

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 1 } ->
    "WindowsXP" (* no architecture differentiation of XP on RHEV *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_product_name = product } when string_find product "XP" >= 0 ->
    "WindowsXP" (* no architecture differentiation of XP on RHEV *)

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_arch = "i386" } ->
    "Windows2003"

  | { i_type = "windows"; i_major_version = 5; i_minor_version = 2;
      i_arch = "x86_64" } ->
    "Windows2003x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_arch = "i386" } ->
    "Windows2008"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 0;
      i_arch = "x86_64" } ->
    "Windows2008x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "i386" } ->
    "Windows7"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "x86_64"; i_product_variant = "Client" } ->
    "Windows7x64"

  | { i_type = "windows"; i_major_version = 6; i_minor_version = 1;
      i_arch = "x86_64" } ->
    "Windows2008R2x64"

  | { i_type = typ; i_distro = distro;
      i_major_version = major; i_minor_version = minor;
      i_product_name = product } ->
    warning ~prog (f_"unknown guest operating system: %s %s %d.%d (%s)")
      typ distro major minor product;
    "Unassigned"
