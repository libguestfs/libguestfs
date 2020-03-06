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

open Unix
open Printf

open Tools_utils
open Common_gettext.Gettext

open Utils
open Cmdline

module G = Guestfs

let () = Random.self_init ()

let rec main () =
  let cmdline = parse_cmdline () in

  (match cmdline.mode with
  | Mode_copying (outdisk, check_tmpdir, compress, convert, option, tmp) ->
    Copying.run cmdline.indisk outdisk check_tmpdir compress convert
                cmdline.format cmdline.ignores option tmp cmdline.zeroes
                cmdline.ks
  | Mode_in_place ->
    In_place.run cmdline.indisk cmdline.format cmdline.ignores cmdline.zeroes
                 cmdline.ks
  )

let () = run_main_and_handle_errors main
