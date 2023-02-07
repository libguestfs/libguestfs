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

let close_invoked = ref 0

let close _ _ _ _ =
  incr close_invoked

let () =
  let g = new Guestfs.guestfs () in
  ignore (g#set_event_callback close [Guestfs.EVENT_CLOSE]);
  assert (!close_invoked = 0);
  g#close ();
  assert (!close_invoked = 1)

let () = Gc.compact ()
