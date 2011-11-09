(* libguestfs OCaml bindings
 * Copyright (C) 2011 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Printf

let log g ev eh buf array =
  let ev =
    match ev with
    | Guestfs.EVENT_CLOSE -> "close"
    | Guestfs.EVENT_SUBPROCESS_QUIT -> "subprocess_quit"
    | Guestfs.EVENT_LAUNCH_DONE -> "launch_done"
    | Guestfs.EVENT_PROGRESS -> "progress"
    | Guestfs.EVENT_APPLIANCE -> "appliance"
    | Guestfs.EVENT_LIBRARY -> "library"
    | Guestfs.EVENT_TRACE -> "trace"
    | Guestfs.EVENT_ENTER -> "enter" in

  let eh : int = Obj.magic eh in

  printf "ocaml event logged: event=%s eh=%d buf=%S array=[%s]\n"
    ev eh buf
    (String.concat ", " (List.map Int64.to_string (Array.to_list array)))

let close_invoked = ref 0

let close g ev eh buf array =
  incr close_invoked;
  log g ev eh buf array

let () =
  let g = new Guestfs.guestfs () in

  (* Grab log, trace and daemon messages into our own custom handler
   * which prints the messages with a particular prefix.
   *)
  let events = [Guestfs.EVENT_APPLIANCE; Guestfs.EVENT_LIBRARY;
                Guestfs.EVENT_TRACE] in
  ignore (g#set_event_callback log events);

  (* Check that the close event is invoked. *)
  ignore (g#set_event_callback close [Guestfs.EVENT_CLOSE]);

  (* Now make sure we see some messages. *)
  g#set_trace true;
  g#set_verbose true;

  (* Do some stuff. *)
  g#add_drive_ro "/dev/null";
  g#set_autosync true;

  (* Close the handle -- should call the close callback. *)
  assert (!close_invoked = 0);
  g#close ();
  assert (!close_invoked = 1);

  (* Run full garbage collection. *)
  Gc.compact ()
