(* virt-sparsify
 * Copyright (C) 2010-2011 Red Hat Inc.
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

open Printf

open Utils

module G = Guestfs

type progress_bar
external progress_bar_init : machine_readable:bool -> progress_bar
  = "virt_sparsify_progress_bar_init"
external progress_bar_reset : progress_bar -> unit
  = "virt_sparsify_progress_bar_reset"
external progress_bar_set : progress_bar -> int64 -> int64 -> unit
  = "virt_sparsify_progress_bar_set"

let set_up_progress_bar ?(machine_readable = false) (g : Guestfs.guestfs) =
  (* Initialize the C mini library. *)
  let bar = progress_bar_init ~machine_readable in

  (* Reset the progress bar before every libguestfs function. *)
  let enter_callback g event evh buf array =
    if event = G.EVENT_ENTER then
      progress_bar_reset bar
  in

  (* A progress event: move the progress bar. *)
  let progress_callback g event evh buf array =
    if event = G.EVENT_PROGRESS && Array.length array >= 4 then (
      let position = array.(2)
      and total = array.(3) in

      progress_bar_set bar position total
    )
  in

  ignore (g#set_event_callback enter_callback [G.EVENT_ENTER]);
  ignore (g#set_event_callback progress_callback [G.EVENT_PROGRESS])
