(* virt-sparsify
 * Copyright (C) 2011-2020 Red Hat Inc.
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
  indisk : string;
  format : string option;
  ignores : string list;
  zeroes : string list;
  mode : mode_t;
  ks : Tools_utils.key_store;
}

and mode_t =
| Mode_copying of
    string * check_t * bool * string option * string option * string option
| Mode_in_place
and check_t = [`Ignore|`Continue|`Warn|`Fail]

val parse_cmdline : unit -> cmdline
