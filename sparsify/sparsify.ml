(* virt-sparsify
 * Copyright (C) 2011-2015 Red Hat Inc.
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

open Unix
open Printf

open Common_utils
open Common_gettext.Gettext

open Utils
open Cmdline

module G = Guestfs

let () = Random.self_init ()

let rec main () =
  let indisk, debug_gc, format, ignores, machine_readable, zeroes, mode =
    parse_cmdline () in

  (match mode with
  | Mode_copying (outdisk, check_tmpdir, compress, convert, option, tmp) ->
    Copying.run indisk outdisk check_tmpdir compress convert
      format ignores machine_readable option tmp zeroes
  | Mode_in_place ->
    In_place.run indisk format ignores machine_readable zeroes
  );

  if debug_gc then
    Gc.compact ()

let () = run_main_and_handle_errors main
