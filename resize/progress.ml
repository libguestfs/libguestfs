(* virt-resize
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

let set_up_progress_bar (g : Guestfs.guestfs) =
  let progress_callback g event evh buf array =
    if event = G.EVENT_PROGRESS && Array.length array >= 4 then (
      (*let proc_nr = array.(0)
      and serial = array.(1)*)
      let position = array.(2)
      and total = array.(3) in

      let ratio =
        if total <> 0L then Int64.to_float position /. Int64.to_float total
        else 0. in
      let ratio =
        if ratio < 0. then 0. else if ratio > 1. then 1. else ratio in

      let dots = int_of_float (ratio *. 72.) in

      print_string "[";
      for i = 0 to dots-1 do print_char '#' done;
      for i = dots to 71 do print_char '-' done;
      print_string "]\r";
      if ratio = 1. then print_string "\n";
      flush stdout
    )
  in
  ignore (g#set_event_callback progress_callback [G.EVENT_PROGRESS])
