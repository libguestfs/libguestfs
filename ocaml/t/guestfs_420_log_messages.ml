(* libguestfs OCaml tests
 * Copyright (C) 2009-2023 Red Hat Inc.
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

let log_invoked = ref 0

let log ev eh buf array =
  let eh : int = Obj.magic eh in

  printf "event logged: event=%s eh=%d buf=%S array=[%s]\n"
    (Guestfs.event_to_string [ev]) eh buf
    (String.concat ", " (List.map Int64.to_string (Array.to_list array)));

  incr log_invoked

let () =
  let g = new Guestfs.guestfs () in
  let events = [ Guestfs.EVENT_APPLIANCE; Guestfs.EVENT_LIBRARY;
                 Guestfs.EVENT_WARNING; Guestfs.EVENT_TRACE ] in
  ignore (g#set_event_callback log events);

  g#set_trace true;
  g#set_verbose true;
  g#add_drive_ro "/dev/null";
  g#set_autosync true;

  g#close ();

  assert (!log_invoked > 0)

let () = Gc.compact ()
