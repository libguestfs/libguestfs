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

open Common_gettext.Gettext
open Common_utils

open Unix

let filter_arch = function
  | "amd64" | "x86_64" | "x64" -> "x86_64"
  | "powerpc" | "ppc" -> "ppc"
  | arch -> arch

let arch_is_compatible nativearch otherarch =
  let nativearch = filter_arch nativearch in
  let otherarch = filter_arch otherarch in
  match nativearch, otherarch with
  | a, b when a = b -> true
  | "x86_64", "i386" -> true
  | "ppc64", "ppc" -> true
  | "sparc64", "sparc" -> true
  | a, b -> false

let current_arch =
  try filter_arch ((Uname.uname ()).Uname.machine)
  with Unix_error _ -> "unknown"
