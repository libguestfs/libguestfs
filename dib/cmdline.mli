(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

(** Command line argument parsing. *)

type cmdline = {
  debug : int;
  basepath : string;
  elements : string list;
  excluded_elements : string list;
  element_paths : string list;
  excluded_scripts : string list;
  use_base : bool;
  drive : string option;
  drive_format : string option;
  image_name : string;
  fs_type : string;
  size : int64;
  root_label : string option;
  install_type : string;
  image_cache : string option;
  compressed : bool;
  qemu_img_options : string option;
  mkfs_options : string option;
  is_ramdisk : bool;
  ramdisk_element : string;
  extra_packages : string list;
  memsize : int option;
  network : bool;
  smp : int option;
  delete_on_failure : bool;
  formats : string list;
  arch : string;
  envvars : string list;
  docker_target : string option;
}

val parse_cmdline : unit -> cmdline
