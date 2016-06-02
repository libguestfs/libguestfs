(* virt-builder
 * Copyright (C) 2013-2016 Red Hat Inc.
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
  mode : [ `Cache_all | `Delete_cache | `Get_kernel | `Install | `List
           | `Notes | `Print_cache ];
  arg : string;
  arch : string;
  attach : (string option * string) list;
  cache : string option;
  check_signature : bool;
  curl : string;
  delete_on_failure : bool;
  format : string option;
  gpg : string;
  list_format : [`Short|`Long|`Json];
  memsize : int option;
  network : bool;
  ops : Customize_cmdline.ops;
  output : string option;
  size : int64 option;
  smp : int option;
  sources : (string * string) list;
  sync : bool;
  warn_if_partition : bool;
}

val parse_cmdline : unit -> cmdline
