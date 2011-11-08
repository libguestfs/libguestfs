(* libguestfs OCaml bindings
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

module G = Guestfs

let () =
  let g = G.create () in

  G.add_drive g "/dev/null";
  G.launch g;

  let calls = ref 0 in
  let cb _ _ _ _ _ = incr calls in
  let eh = G.set_event_callback g cb [G.EVENT_PROGRESS] in
  assert ("ok" = G.debug g "progress" [| "5" |]);
  assert (!calls > 0);
  calls := 0;
  G.delete_event_callback g eh;
  assert ("ok" = G.debug g "progress" [| "5" |]);
  assert (!calls = 0);
  ignore (G.set_event_callback g cb [G.EVENT_PROGRESS]);
  assert ("ok" = G.debug g "progress" [| "5" |]);
  assert (!calls > 0);

  G.close g;
  Gc.compact ()
