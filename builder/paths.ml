(* virt-builder
 * Copyright (C) 2014 Red Hat Inc.
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

open Common_utils

let xdg_cache_home =
  try Some (Sys.getenv "XDG_CACHE_HOME" // "virt-builder")
  with Not_found ->
    try Some (Sys.getenv "HOME" // ".cache" // "virt-builder")
    with Not_found ->
      None (* no cache directory *)

let xdg_config_home ~prog =
  try Some (Sys.getenv "XDG_CONFIG_HOME" // prog)
  with Not_found ->
    try Some (Sys.getenv "HOME" // ".config" // prog)
    with Not_found ->
      None (* no config directory *)

let xdg_config_dirs ~prog =
  let dirs =
    try Sys.getenv "XDG_CONFIG_DIRS"
    with Not_found -> "/etc/xdg" in
  let dirs = string_nsplit ":" dirs in
  let dirs = List.filter (fun x -> x <> "") dirs in
  List.map (fun x -> x // prog) dirs
