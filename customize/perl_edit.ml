(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

open Std_utils
open Common_utils

external c_edit_file : verbose:bool -> Guestfs.t -> int64 -> string -> string -> unit
  = "virt_customize_edit_file_perl"
let edit_file g file expr =
  (* Note we pass original 'g' even though it is not used by the
   * callee.  This is so that 'g' is kept as a root on the stack, and
   * so cannot be garbage collected while we are in the c_edit_file
   * function.
   *)
  c_edit_file (verbose ()) g (Guestfs.c_pointer g) file expr
