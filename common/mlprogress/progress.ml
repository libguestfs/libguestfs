(* libguestfs OCaml tools common code
 * Copyright (C) 2010-2018 Red Hat Inc.
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

module G = Guestfs

type progress_bar
external progress_bar_init : machine_readable:bool -> progress_bar
  = "guestfs_int_mllib_progress_bar_init"
external progress_bar_reset : progress_bar -> unit
  = "guestfs_int_mllib_progress_bar_reset" "noalloc"
external progress_bar_set : progress_bar -> int64 -> int64 -> unit
  = "guestfs_int_mllib_progress_bar_set" "noalloc"

let set_up_progress_bar ?(machine_readable = false) (g : Guestfs.guestfs) =
  (* Only display progress bars if the machine_readable flag is set or
   * the output is a tty.
   *)
  if machine_readable || Unix.isatty Unix.stdout then (
    (* Initialize the C mini library. *)
    let bar = progress_bar_init ~machine_readable in

    (* Reset the progress bar before every libguestfs function. *)
    let enter_callback event evh buf array =
      if event = G.EVENT_ENTER then
        progress_bar_reset bar
    in

    (* A progress event: move the progress bar. *)
    let progress_callback event evh buf array =
      if event = G.EVENT_PROGRESS && Array.length array >= 4 then (
        let position = array.(2)
        and total = array.(3) in

        progress_bar_set bar position total
      )
    in

    ignore (g#set_event_callback enter_callback [G.EVENT_ENTER]);
    ignore (g#set_event_callback progress_callback [G.EVENT_PROGRESS])
  )
